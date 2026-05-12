param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$ConfigPath = "..\config\robot.psd1",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig
$resolvedSpec = Resolve-Path -LiteralPath $SpecPath

$specValidator = Join-Path $scriptRoot "Test-FanucProgramSpec.ps1"
& $specValidator -SpecPath $resolvedSpec -ConfigPath $resolvedConfig -Quiet

$spec = (Get-Content -LiteralPath $resolvedSpec -Raw) | ConvertFrom-Json
$programName = $spec.programName.ToUpperInvariant()

function Format-FanucMessage {
    param([string]$Text)

    $safeText = $Text.ToUpperInvariant() -replace '[^\w \-]', ''
    if ($safeText.Length -eq 0) {
        throw "Message became empty after safety filtering."
    }
    if ($safeText.Length -gt 24) {
        throw "FANUC MESSAGE text should stay short. Use 24 characters or fewer."
    }
    return $safeText
}

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

$mnLines = New-Object System.Collections.Generic.List[string]
$lineNumber = 1
foreach ($operation in @($spec.operations)) {
    switch ($operation.type) {
        "message" {
            $message = Format-FanucMessage $operation.text
            $mnLines.Add((" {0,3}:  MESSAGE[{1}] ;" -f $lineNumber, $message))
        }
        "registerWrite" {
            $mnLines.Add((" {0,3}:  R[{1}]={2} ;" -f $lineNumber, [int]$operation.register, [int]$operation.value))
        }
        "ioWrite" {
            $state = if ($operation.state) { "ON" } else { "OFF" }
            $mnLines.Add((" {0,3}:  {1}={2} ;" -f $lineNumber, $operation.signal.ToUpperInvariant(), $state))
        }
        "wait" {
            $seconds = [double]$operation.seconds
            $mnLines.Add((" {0,3}:  WAIT {1:0.00}(sec) ;" -f $lineNumber, $seconds))
        }
        "comment" {
            $comment = Format-FanucComment $operation.text
            $mnLines.Add((" {0,3}:  ! {1} ;" -f $lineNumber, $comment))
        }
        "diagnosticCheck" {
            $label = Format-FanucComment ($operation.name + " " + $operation.text)
            $mnLines.Add((" {0,3}:  ! {1} ;" -f $lineNumber, $label))
        }
        "callProgram" {
            $mnLines.Add((" {0,3}:  CALL {1} ;" -f $lineNumber, $operation.program.ToUpperInvariant()))
        }
        default {
            throw "Unsupported operation type: $($operation.type)"
        }
    }
    $lineNumber++
}

$sourcesDir = Join-Path $projectRoot "generated\sources"
$jobDir = Join-Path (Join-Path $projectRoot "generated\jobs") $programName
$jobSourcePath = Join-Path $jobDir ($programName + ".LS")
$sourcePath = Join-Path $sourcesDir ($programName + ".LS")
$jobSpecPath = Join-Path $jobDir "spec.json"

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
COMMENT = "AI SPEC GEN";
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
    SourcePath = (Get-Item -LiteralPath $sourcePath).FullName
    JobDirectory = (Get-Item -LiteralPath $jobDir).FullName
    JobSourcePath = (Get-Item -LiteralPath $jobSourcePath).FullName
    JobSpecPath = (Get-Item -LiteralPath $jobSpecPath).FullName
}
