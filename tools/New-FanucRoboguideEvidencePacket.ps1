param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$ConfigPath = "..\config\roboguide-evidence.psd1",
    [string]$OutputPath,
    [switch]$WriteMarkdown,
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

    return Join-Path $projectRoot $Path
}

function Resolve-InputPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return (Resolve-Path -LiteralPath (Join-Path $scriptRoot $Path)).Path
}

$resolvedSpecPath = Resolve-InputPath -Path $SpecPath
$resolvedConfigPath = Resolve-InputPath -Path $ConfigPath

$configValidator = Join-Path $scriptRoot "Test-FanucRoboguideEvidenceConfig.ps1"
$specValidator = Join-Path $scriptRoot "Test-FanucProgramSpec.ps1"
& $configValidator -ConfigPath $resolvedConfigPath -Quiet
& $specValidator -SpecPath $resolvedSpecPath -Quiet

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath
$spec = Get-Content -LiteralPath $resolvedSpecPath -Raw | ConvertFrom-Json
$program = $spec.programName.ToUpperInvariant()

$hasIoWrites = @($spec.operations | Where-Object { $_.type -eq "ioWrite" }).Count -gt 0
$evidenceClass = if ([bool]$spec.safety.motionAllowed) {
    "motion"
} elseif ($hasIoWrites) {
    "io-sequence"
} else {
    "no-motion"
}
$policy = @($config.EvidenceClasses | Where-Object { $_.Name -eq $evidenceClass } | Select-Object -First 1)

if (-not $OutputPath) {
    $OutputPath = "generated\jobs\$program\roboguide-evidence-packet.json"
}
$resolvedOutputPath = Resolve-ProjectPath $OutputPath
if ((Test-Path -LiteralPath $resolvedOutputPath) -and -not $Force) {
    throw "RoboGuide evidence packet already exists: $resolvedOutputPath. Use -Force to overwrite."
}

$registerWrites = @($spec.operations | Where-Object { $_.type -eq "registerWrite" } | ForEach-Object {
    [ordered]@{
        register = "R[$([int]$_.register)]"
        value = [int]$_.value
    }
})
$ioWrites = @($spec.operations | Where-Object { $_.type -eq "ioWrite" } | ForEach-Object {
    [ordered]@{
        signal = $_.signal.ToUpperInvariant()
        state = if ([bool]$_.state) { "ON" } else { "OFF" }
    }
})

$steps = New-Object System.Collections.Generic.List[object]
$stepNumber = 1
$steps.Add([ordered]@{ step = $stepNumber++; name = "Open workcell"; expected = "Intended RoboGuide workcell is open and controller version is reviewed." })
$steps.Add([ordered]@{ step = $stepNumber++; name = "Load program"; expected = "$program.TP is loaded or present on the virtual controller." })
$steps.Add([ordered]@{ step = $stepNumber++; name = "Review safety"; expected = "MotionAllowed=$($spec.safety.motionAllowed); human review is complete before running." })
if ([bool]$policy.RequiresBeforeAfterSnapshot) {
    $steps.Add([ordered]@{ step = $stepNumber++; name = "Capture before snapshot"; expected = "Record relevant registers, IO, frames/tools, and mode before execution." })
}
$steps.Add([ordered]@{ step = $stepNumber++; name = "Execute or inspect"; expected = "Run in RoboGuide when required, or inspect/checklist in controlled manual mode for no-motion programs." })
if ([bool]$policy.RequiresBeforeAfterSnapshot) {
    $steps.Add([ordered]@{ step = $stepNumber++; name = "Capture after snapshot"; expected = "Record relevant registers, IO, frames/tools, and mode after execution." })
}
$steps.Add([ordered]@{ step = $stepNumber++; name = "Record result"; expected = "Record passed/failed/not-required, reviewer, date, and notes." })

$packet = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    programName = $program
    specPath = (Get-Item -LiteralPath $resolvedSpecPath).FullName
    evidenceClass = $evidenceClass
    roboguideRequired = [bool]$policy.RoboguideRequired
    manualT1Required = [bool]$policy.ManualT1Required
    requiresBeforeAfterSnapshot = [bool]$policy.RequiresBeforeAfterSnapshot
    requiredSections = @($policy.RequiredSections)
    intent = $spec.intent
    safety = $spec.safety
    expectedWrites = [ordered]@{
        registers = $registerWrites
        ioSignals = $ioWrites
    }
    steps = @($steps.ToArray())
    result = [ordered]@{
        status = "pending"
        reviewer = ""
        date = ""
        workcellPath = ""
        notes = ""
    }
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$packet | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

$markdownPath = $null
if ($WriteMarkdown) {
    $markdownPath = [System.IO.Path]::ChangeExtension($resolvedOutputPath, ".md")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# RoboGuide Evidence Packet: $program")
    $lines.Add("")
    $lines.Add("- Evidence class: $evidenceClass")
    $lines.Add("- RoboGuide required: $([bool]$policy.RoboguideRequired)")
    $lines.Add("- Manual T1 required: $([bool]$policy.ManualT1Required)")
    $lines.Add("- Before/after snapshot required: $([bool]$policy.RequiresBeforeAfterSnapshot)")
    $lines.Add("")
    $lines.Add("## Intent")
    $lines.Add("")
    $lines.Add($spec.intent)
    $lines.Add("")
    $lines.Add("## Required Sections")
    $lines.Add("")
    foreach ($section in @($policy.RequiredSections)) {
        $lines.Add("- $section")
    }
    $lines.Add("")
    $lines.Add("## Expected Writes")
    $lines.Add("")
    foreach ($write in $registerWrites) {
        $lines.Add("- $($write.register) = $($write.value)")
    }
    foreach ($write in $ioWrites) {
        $lines.Add("- $($write.signal) = $($write.state)")
    }
    if ($registerWrites.Count -eq 0 -and $ioWrites.Count -eq 0) {
        $lines.Add("- none")
    }
    $lines.Add("")
    $lines.Add("## Steps")
    $lines.Add("")
    foreach ($step in @($steps.ToArray())) {
        $lines.Add("$($step.step). $($step.name): $($step.expected)")
    }
    $lines.Add("")
    $lines.Add("## Result")
    $lines.Add("")
    $lines.Add("- Status: pending")
    $lines.Add("- Reviewer:")
    $lines.Add("- Date:")
    $lines.Add("- Workcell:")
    $lines.Add("- Notes:")
    $lines | Set-Content -LiteralPath $markdownPath -Encoding ASCII
}

[pscustomobject]@{
    ProgramName = $program
    EvidenceClass = $evidenceClass
    RoboguideRequired = [bool]$policy.RoboguideRequired
    ManualT1Required = [bool]$policy.ManualT1Required
    RequiresBeforeAfterSnapshot = [bool]$policy.RequiresBeforeAfterSnapshot
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
    MarkdownPath = if ($markdownPath) { (Get-Item -LiteralPath $markdownPath).FullName } else { $null }
}
