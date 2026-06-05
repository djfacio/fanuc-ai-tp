param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$ConfigPath = "..\config\robot.psd1",
    [string]$CellMapPath = "..\config\cell-map.psd1",
    [string]$OutputRoot = "generated",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return (Resolve-Path -LiteralPath (Join-Path $projectRoot $Path)).Path
}

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $resolvedOutputRoot = $OutputRoot
} else {
    $resolvedOutputRoot = Join-Path $projectRoot $OutputRoot
}

$resolvedSpec = Resolve-Path -LiteralPath $SpecPath
$validator = Join-Path $scriptRoot "Test-FanucMotionApplicationSpec.ps1"
$validation = & $validator -SpecPath $resolvedSpec -CellMapPath $CellMapPath

if (-not $validation.ReadyForGeneration) {
    $messages = $validation.GenerationGateMessages | ForEach-Object { "- $_" }
    throw "Motion application spec is not ready for generation:`n$($messages -join "`n")"
}

$spec = Get-Content -LiteralPath $resolvedSpec -Raw | ConvertFrom-Json
if (-not [bool]$spec.generation.allowed) {
    throw "Motion generation is not allowed by the spec. Set generation.allowed=true only after review."
}
$supportedTemplates = @("pr-waypoint-sequence-v1", "approach-process-retract-v1", "io-motion-sequence-v1", "motion-action-calc-pr-v1")
if ($supportedTemplates -notcontains $spec.generation.templateId) {
    throw "Unsupported motion templateId '$($spec.generation.templateId)'."
}

$programName = $spec.programName.ToUpperInvariant()

function Format-FanucComment {
    param([string]$Text)

    $safeText = $Text -replace '[^\w \-\.,:/\(\)]', ''
    if ($safeText.Length -eq 0) {
        throw "Comment became empty after safety filtering."
    }
    if ($safeText.Length -gt 31) {
        $safeText = $safeText.Substring(0, 31)
    }
    return $safeText
}

function Format-FanucSpeed {
    param($Speed)

    $value = [double]$Speed.value
    switch ($Speed.unit) {
        "%" {
            if ($value -gt 100) {
                throw "Joint speed percent must be 100 or lower."
            }
            return ("{0:0.###}%" -f $value)
        }
        "mm/sec" { return ("{0:0.###}mm/sec" -f $value) }
        "cm/min" { return ("{0:0.###}cm/min" -f $value) }
        "deg/sec" { return ("{0:0.###}deg/sec" -f $value) }
        default { throw "Unsupported speed unit '$($Speed.unit)'." }
    }
}

function Format-FanucTermination {
    param($Termination)

    if ($Termination.type -eq "FINE") {
        return "FINE"
    }
    return ("CNT{0}" -f [int]$Termination.value)
}

function Format-FanucIoState {
    param([bool]$State)

    if ($State) {
        return "ON"
    }
    return "OFF"
}

$mnLines = New-Object System.Collections.Generic.List[string]
$lineNumber = 1
$templateId = [string]$spec.generation.templateId

$mnLines.Add((" {0,3}:  ! {1} ;" -f $lineNumber, (Format-FanucComment "AI REVIEWED MOTION TEMPLATE")))
$lineNumber++
$mnLines.Add((" {0,3}:  PAYLOAD[{1}] ;" -f $lineNumber, [int]$spec.resources.payload.number))
$lineNumber++

if ($templateId -ne "motion-action-calc-pr-v1") {
    $mnLines.Insert(1, (" {0,3}:  UFRAME_NUM={1} ;" -f 2, [int]$spec.resources.userFrame.number))
    $mnLines.Insert(2, (" {0,3}:  UTOOL_NUM={1} ;" -f 3, [int]$spec.resources.userTool.number))
    for ($i = 3; $i -lt $mnLines.Count; $i++) {
        $mnLines[$i] = [regex]::Replace($mnLines[$i], '^\s*\d+\s*:', (" {0,3}:" -f ($i + 1)))
    }
    $lineNumber = $mnLines.Count + 1
} elseif ([bool]$spec.motionPlan.positionArchitecture.calcProgram.required -and [bool]$spec.motionPlan.positionArchitecture.calcProgram.callBeforeMotion) {
    $mnLines.Add((" {0,3}:  ! {1} ;" -f $lineNumber, (Format-FanucComment "Calculate visible PRs")))
    $lineNumber++
    $mnLines.Add((" {0,3}:  CALL {1} ;" -f $lineNumber, $spec.motionPlan.positionArchitecture.calcProgram.programName.ToUpperInvariant()))
    $lineNumber++
}

$ioSequence = @()
if ($null -ne $spec.motionPlan.PSObject.Properties["ioSequence"]) {
    $ioSequence = @($spec.motionPlan.ioSequence)
}

foreach ($step in @($spec.motionPlan.motionSequence)) {
    foreach ($ioAction in @($ioSequence | Where-Object { $_.stepName -eq $step.stepName -and $_.position -eq "before" })) {
        $state = Format-FanucIoState ([bool]$ioAction.state)
        $mnLines.Add((" {0,3}:  {1}={2} ;" -f $lineNumber, $ioAction.signal.ToUpperInvariant(), $state))
        $lineNumber++
    }

    $mnLines.Add((" {0,3}:  ! {1} ;" -f $lineNumber, (Format-FanucComment $step.stepName)))
    $lineNumber++

    if ($templateId -eq "motion-action-calc-pr-v1") {
        $mnLines.Add((" {0,3}:  UFRAME_NUM={1} ;" -f $lineNumber, [int]$spec.resources.userFrame.number))
        $lineNumber++
        $mnLines.Add((" {0,3}:  UTOOL_NUM={1} ;" -f $lineNumber, [int]$spec.resources.userTool.number))
        $lineNumber++
    }

    $motionType = $step.motionType.ToUpperInvariant()
    $target = "PR[$([int]$step.target.number)]"
    $speed = Format-FanucSpeed $step.speed
    $termination = Format-FanucTermination $step.termination
    $mnLines.Add((" {0,3}:{1} {2} {3} {4} ;" -f $lineNumber, $motionType, $target, $speed, $termination))
    $lineNumber++

    if ($templateId -eq "motion-action-calc-pr-v1") {
        $breadcrumbRegister = [int]$spec.motionPlan.positionArchitecture.breadcrumb.register
        $mnLines.Add((" {0,3}:  R[{1}]={2} ;" -f $lineNumber, $breadcrumbRegister, [int]$step.target.number))
        $lineNumber++
    }

    foreach ($ioAction in @($ioSequence | Where-Object { $_.stepName -eq $step.stepName -and $_.position -eq "after" })) {
        $state = Format-FanucIoState ([bool]$ioAction.state)
        $mnLines.Add((" {0,3}:  {1}={2} ;" -f $lineNumber, $ioAction.signal.ToUpperInvariant(), $state))
        $lineNumber++
    }
}

$sourcesDir = Join-Path $resolvedOutputRoot "sources"
$jobDir = Join-Path (Join-Path $resolvedOutputRoot "jobs") $programName
$sourcePath = Join-Path $sourcesDir ($programName + ".LS")
$jobSourcePath = Join-Path $jobDir ($programName + ".LS")
$jobSpecPath = Join-Path $jobDir "motion-application-spec.json"

foreach ($path in @($sourcesDir, $jobDir)) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

foreach ($path in @($sourcePath, $jobSourcePath, $jobSpecPath)) {
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        throw "Output already exists: $path. Use -Force to overwrite."
    }
}

$now = Get-Date
$date = $now.ToString("yy-MM-dd")
$time = $now.ToString("HH:mm:ss")
$lineCount = $mnLines.Count
$mnText = $mnLines -join "`n"

$content = @"
/PROG $programName
/ATTR
OWNER = MNEDITOR;
COMMENT = "AI MOTION GEN";
PROG_SIZE = 0;
CREATE = DATE $date  TIME $time;
MODIFIED = DATE $date  TIME $time;
FILE_NAME = ;
VERSION = 0;
LINE_COUNT = $lineCount;
MEMORY_SIZE = 0;
PROTECT = READ_WRITE;
TCD: STACK_SIZE = 0,
     TASK_PRIORITY = 50,
     TIME_SLICE = 0,
     BUSY_LAMP_OFF = 0,
     ABORT_REQUEST = 0,
     PAUSE_REQUEST = 0;
DEFAULT_GROUP = 1,*,*,*,*;
CONTROL_CODE = 00000000 00000000;
/MN
$mnText
/POS
/END
"@

Set-Content -LiteralPath $sourcePath -Value $content -Encoding ASCII
Set-Content -LiteralPath $jobSourcePath -Value $content -Encoding ASCII
Copy-Item -LiteralPath $resolvedSpec -Destination $jobSpecPath -Force

$safetyTool = Join-Path $scriptRoot "Test-FanucLsSafety.ps1"
& $safetyTool -LsPath $sourcePath -ProgramName $programName -ConfigPath $resolvedConfig -Quiet

[pscustomobject]@{
    ProgramName = $programName
    TemplateId = $spec.generation.templateId
    SourcePath = (Get-Item -LiteralPath $sourcePath).FullName
    JobDirectory = (Get-Item -LiteralPath $jobDir).FullName
    JobSourcePath = (Get-Item -LiteralPath $jobSourcePath).FullName
    JobSpecPath = (Get-Item -LiteralPath $jobSpecPath).FullName
    ControllerWritesExecuted = $false
    LiveRobotCommandsExecuted = $false
}
