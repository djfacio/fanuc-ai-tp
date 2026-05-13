param(
    [Parameter(Mandatory = $true)]
    [string]$LsPath,

    [string]$ConfigPath = "..\config\robot.psd1",
    [string]$OutputRoot = "generated",
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
$configRoot = Split-Path -Parent $resolvedConfig

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $projectRoot $Path
}

function Resolve-ConfigOrProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    $projectCandidate = Join-Path $projectRoot $Path
    if (Test-Path -LiteralPath $projectCandidate) {
        return $projectCandidate
    }

    return Join-Path $configRoot $Path
}

if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $resolvedOutputRoot = $OutputRoot
} else {
    $resolvedOutputRoot = Join-Path $projectRoot $OutputRoot
}

function Get-FanucMnInstructions {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($text, '(?is)/MN\s*(.*?)\s*/POS')
    if (-not $match.Success) {
        throw "Could not find /MN section in $Path"
    }

    $lines = $match.Groups[1].Value -split '\r?\n'
    $instructions = New-Object System.Collections.Generic.List[string]
    foreach ($line in $lines) {
        $normalized = $line.Trim()
        if ($normalized.Length -eq 0) {
            continue
        }

        $normalized = [regex]::Replace($normalized, '^\d+\s*:\s*', '')
        $normalized = [regex]::Replace($normalized, '\s+', ' ')
        $normalized = [regex]::Replace($normalized, '(?i)\b(DO|RO)\[(\d+)\s*:\s*\*\s*\]', '$1[$2]')
        $normalized = [regex]::Replace($normalized, '(?i)\bPR\[(\d+)\s*:\s*[^\]]+\]', 'PR[$1]')
        $normalized = [regex]::Replace($normalized, '(?i)\bWAIT\s+\.([0-9]+)\(SEC\)', 'WAIT 0.$1(SEC)')
        $normalized = [regex]::Replace($normalized, '\s*=\s*', '=')
        $normalized = [regex]::Replace($normalized, '\s*;\s*$', ' ;')
        $normalized = $normalized.Trim().ToUpperInvariant()
        $instructions.Add($normalized)
    }

    return $instructions.ToArray()
}

function Get-FanucProgramSummary {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw
    $programMatch = [regex]::Match($text, '(?im)^\s*/PROG\s+([A-Za-z][A-Za-z0-9_]*)\s*$')
    $lineCountMatch = [regex]::Match($text, '(?im)^\s*LINE_COUNT\s*=\s*([0-9]+)\s*;')
    $defaultGroupMatch = [regex]::Match($text, '(?im)^\s*DEFAULT_GROUP\s*=\s*([^;]+)\s*;')

    return [ordered]@{
        programName = if ($programMatch.Success) { $programMatch.Groups[1].Value.ToUpperInvariant() } else { $null }
        lineCount = if ($lineCountMatch.Success) { [int]$lineCountMatch.Groups[1].Value } else { $null }
        defaultGroup = if ($defaultGroupMatch.Success) { ($defaultGroupMatch.Groups[1].Value -replace '\s+', '').ToUpperInvariant() } else { $null }
        hasApplSection = [bool]([regex]::IsMatch($text, '(?im)^\s*/APPL\s*$'))
    }
}

$resolvedLs = Resolve-Path -LiteralPath $LsPath
$lsItem = Get-Item -LiteralPath $resolvedLs
$programName = $lsItem.BaseName.ToUpperInvariant()
$jobDir = Join-Path (Join-Path $resolvedOutputRoot "jobs") $programName
$compiledPath = Join-Path (Join-Path $resolvedOutputRoot "compiled") ($programName + ".TP")
$jobCompiledPath = Join-Path $jobDir ($programName + ".TP")
$decodedPath = Join-Path $jobDir "decoded.LS"
$reportPath = Join-Path $jobDir "roundtrip.json"

foreach ($path in @($jobDir)) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

foreach ($path in @($decodedPath, $reportPath)) {
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        throw "Round-trip output already exists: $path. Use -Force to overwrite."
    }
}

$winOlpcLockDir = Join-Path $resolvedOutputRoot "compiled"
if (-not (Test-Path -LiteralPath $winOlpcLockDir)) {
    New-Item -ItemType Directory -Path $winOlpcLockDir -Force | Out-Null
}
$winOlpcLockPath = Join-Path $winOlpcLockDir ".winolpc.lock"
$winOlpcLock = $null
$printTpOutput = @()
try {
    $deadline = (Get-Date).AddMinutes(2)
    while ($null -eq $winOlpcLock) {
        try {
            $winOlpcLock = [System.IO.File]::Open($winOlpcLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch [System.IO.IOException] {
            if ((Get-Date) -ge $deadline) {
                throw "Timed out waiting for WinOLPC round-trip lock: $winOlpcLockPath"
            }
            Start-Sleep -Milliseconds 250
        }
    }

    $buildTool = Join-Path $scriptRoot "Invoke-FanucTpBuild.ps1"
    & $buildTool -LsPath $lsItem.FullName -ConfigPath $resolvedConfig -OutputRoot $resolvedOutputRoot -Force

    if (-not (Test-Path -LiteralPath $compiledPath)) {
        throw "Compile completed but TP file was not found: $compiledPath"
    }

    Copy-Item -LiteralPath $compiledPath -Destination $jobCompiledPath -Force

    $robotIniPath = Resolve-ConfigOrProjectPath $config.RobotIniPath
    $printTpPath = Join-Path (Split-Path -Parent $config.MakeTpPath) "printtp.exe"
    if (-not (Test-Path -LiteralPath $printTpPath)) {
        throw "PrintTP not found: $printTpPath"
    }

    if (Test-Path -LiteralPath $decodedPath) {
        Remove-Item -LiteralPath $decodedPath -Force
    }

    Write-Host "Decoding $compiledPath"
    $printTpOutput = & $printTpPath $compiledPath $decodedPath /config $robotIniPath /ver $config.WinOlpcVersion 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "PrintTP failed with exit code $LASTEXITCODE`n$($printTpOutput -join "`n")"
    }

    if (-not (Test-Path -LiteralPath $decodedPath)) {
        throw "PrintTP completed but decoded LS was not created: $decodedPath"
    }
}
finally {
    if ($null -ne $winOlpcLock) {
        $winOlpcLock.Dispose()
    }
}

$sourceInstructions = Get-FanucMnInstructions -Path $lsItem.FullName
$decodedInstructions = Get-FanucMnInstructions -Path $decodedPath
$instructionMatch = (($sourceInstructions -join "`n") -eq ($decodedInstructions -join "`n"))
$sourceSummary = Get-FanucProgramSummary -Path $lsItem.FullName
$decodedSummary = Get-FanucProgramSummary -Path $decodedPath
$programNameMatch = ($sourceSummary.programName -eq $decodedSummary.programName)
$lineCountMatch = ($sourceSummary.lineCount -eq $decodedSummary.lineCount)
$defaultGroupMatch = ($sourceSummary.defaultGroup -eq $decodedSummary.defaultGroup)
$unexpectedApplSection = (-not [bool]$sourceSummary.hasApplSection -and [bool]$decodedSummary.hasApplSection)
$overallMatch = ($instructionMatch -and $programNameMatch -and $lineCountMatch -and $defaultGroupMatch)

$report = [ordered]@{
    timestamp = (Get-Date).ToString("o")
    programName = $programName
    sourcePath = $lsItem.FullName
    compiledPath = (Get-Item -LiteralPath $compiledPath).FullName
    jobCompiledPath = (Get-Item -LiteralPath $jobCompiledPath).FullName
    decodedPath = (Get-Item -LiteralPath $decodedPath).FullName
    overallMatch = $overallMatch
    instructionMatch = $instructionMatch
    programNameMatch = $programNameMatch
    lineCountMatch = $lineCountMatch
    defaultGroupMatch = $defaultGroupMatch
    unexpectedApplSection = $unexpectedApplSection
    sourceSummary = $sourceSummary
    decodedSummary = $decodedSummary
    sourceInstructions = $sourceInstructions
    decodedInstructions = $decodedInstructions
    printTpOutput = @($printTpOutput)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding ASCII

if (-not $overallMatch) {
    throw "Round-trip comparison failed. See $reportPath"
}

[pscustomobject]@{
    ProgramName = $programName
    OverallMatch = $overallMatch
    InstructionMatch = $instructionMatch
    ReportPath = (Get-Item -LiteralPath $reportPath).FullName
    DecodedPath = (Get-Item -LiteralPath $decodedPath).FullName
}
