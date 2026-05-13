[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string[]]$ProgramName,
    [switch]$FromInventory,
    [string]$InventoryPath = "generated\robot-inventory\latest.json",
    [int]$Limit = 10,
    [switch]$IncludeAiPrograms,
    [switch]$ExcludeAiPrograms,
    [switch]$ExcludeGeneratedPrograms,
    [string]$OutputRoot = "generated\production-analysis",
    [string]$ConfigPath = "..\config\robot.psd1",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ($ExcludeAiPrograms) {
    $ExcludeGeneratedPrograms = $true
}
if ($IncludeAiPrograms -and $ExcludeGeneratedPrograms) {
    throw "Use only one generated-program policy switch. Generated programs are included by default; use -ExcludeGeneratedPrograms only for a deliberately non-generated view."
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $projectRoot $Path
}

function Get-GeneratedProgramPrefixes {
    param([object]$Config)

    $prefixes = New-Object System.Collections.Generic.List[string]
    if ($Config.ProgramPrefix) {
        $prefixes.Add($Config.ProgramPrefix.ToUpperInvariant())
    }
    foreach ($prefix in @($Config.LegacyProgramPrefixes)) {
        if ($prefix) {
            $prefixes.Add($prefix.ToUpperInvariant())
        }
    }
    return @($prefixes.ToArray() | Sort-Object -Unique)
}

function Test-GeneratedProgramName {
    param(
        [string]$ProgramName,
        [string[]]$Prefixes
    )

    foreach ($prefix in @($Prefixes)) {
        if ($ProgramName.StartsWith($prefix)) {
            return $true
        }
    }
    return $false
}

function Get-LsSummary {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{
            exists = $false
            lineCount = 0
            motionLineCount = 0
            callLineCount = 0
            registerWriteCount = 0
            ioWriteCount = 0
        }
    }

    $lines = Get-Content -LiteralPath $Path
    $mn = $false
    $motion = 0
    $calls = 0
    $registerWrites = 0
    $ioWrites = 0
    foreach ($line in $lines) {
        if ($line -match '^\s*/MN') {
            $mn = $true
            continue
        }
        if ($line -match '^\s*/POS') {
            $mn = $false
        }
        if (-not $mn) {
            continue
        }
        if ($line -match '^\s*\d+:\s*[JL]\s+') {
            $motion++
        }
        if ($line -match '\bCALL\s+') {
            $calls++
        }
        if ($line -match '\bR\[\d+') {
            $registerWrites++
        }
        if ($line -match '\b[DRU]O\[\d+') {
            $ioWrites++
        }
    }

    [ordered]@{
        exists = $true
        lineCount = $lines.Count
        motionLineCount = $motion
        callLineCount = $calls
        registerWriteCount = $registerWrites
        ioWriteCount = $ioWrites
    }
}

if (-not $ProgramName -and -not $FromInventory) {
    throw "Provide -ProgramName or use -FromInventory with an inventory snapshot."
}

$resolvedConfig = if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    (Resolve-Path -LiteralPath $ConfigPath).Path
} else {
    (Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)).Path
}
$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig
$generatedProgramPrefixes = @(Get-GeneratedProgramPrefixes -Config $config)

$programs = @()
if ($ProgramName) {
    $programs += $ProgramName
}

if ($FromInventory) {
    $resolvedInventoryPath = Resolve-ProjectPath $InventoryPath
    if (-not (Test-Path -LiteralPath $resolvedInventoryPath)) {
        throw "Inventory not found: $resolvedInventoryPath. Run Save-FanucRobotInventory.ps1 first."
    }

    $inventory = Get-Content -LiteralPath $resolvedInventoryPath -Raw | ConvertFrom-Json
    $candidates = @($inventory.entries |
        Where-Object { $_.Extension -eq ".TP" } |
        Where-Object { -not $ExcludeGeneratedPrograms -or -not (Test-GeneratedProgramName -ProgramName $_.ProgramName -Prefixes $generatedProgramPrefixes) } |
        Where-Object { $_.ProgramName -match '^[A-Z][A-Z0-9_]{0,31}$' } |
        Sort-Object ProgramName |
        Select-Object -First $Limit)
    $programs += @($candidates | ForEach-Object { $_.ProgramName })
}

$programs = @($programs | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_).ToUpperInvariant() } | Sort-Object -Unique)
if ($programs.Count -eq 0) {
    throw "No production TP candidates selected."
}

$resolvedOutputRoot = Resolve-ProjectPath $OutputRoot
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$analysisRoot = Join-Path $resolvedOutputRoot $stamp
if (-not (Test-Path -LiteralPath $analysisRoot)) {
    New-Item -ItemType Directory -Path $analysisRoot -Force | Out-Null
}

$reader = Join-Path $scriptRoot "Read-FanucTpProgram.ps1"
$results = foreach ($program in $programs) {
    $programDir = Join-Path $analysisRoot $program
    if (-not (Test-Path -LiteralPath $programDir)) {
        New-Item -ItemType Directory -Path $programDir -Force | Out-Null
    }

    $downloadedTp = Join-Path (Join-Path $projectRoot "downloaded\tp") ($program + ".TP")
    $decodedLs = Join-Path (Join-Path $projectRoot "downloaded\ls") ($program + ".LS")
    $analysisPath = Join-Path $programDir "analysis.json"
    $copyTp = Join-Path $programDir ($program + ".TP")
    $copyLs = Join-Path $programDir ($program + ".LS")

    $status = "not-run"
    $errorMessage = $null
    if ($PSCmdlet.ShouldProcess($program, "Download and decode robot TP for read-only analysis")) {
        try {
            & $reader -Program $program -ConfigPath $resolvedConfig -Force:$Force | Out-Null
            if (Test-Path -LiteralPath $downloadedTp) {
                Copy-Item -LiteralPath $downloadedTp -Destination $copyTp -Force
            }
            if (Test-Path -LiteralPath $decodedLs) {
                Copy-Item -LiteralPath $decodedLs -Destination $copyLs -Force
            }
            $status = "decoded"
        } catch {
            $status = "failed"
            $errorMessage = $_.Exception.Message
        }
    }

    $summary = Get-LsSummary -Path $copyLs
    $record = [ordered]@{
        timestamp = (Get-Date).ToString("o")
        programName = $program
        status = $status
        error = $errorMessage
        tpPath = if (Test-Path -LiteralPath $copyTp) { (Get-Item -LiteralPath $copyTp).FullName } else { $null }
        lsPath = if (Test-Path -LiteralPath $copyLs) { (Get-Item -LiteralPath $copyLs).FullName } else { $null }
        summary = $summary
    }
    $record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $analysisPath -Encoding ASCII

    [pscustomobject]@{
        ProgramName = $program
        Status = $status
        MotionLineCount = $summary.motionLineCount
        CallLineCount = $summary.callLineCount
        RegisterWriteCount = $summary.registerWriteCount
        IoWriteCount = $summary.ioWriteCount
        AnalysisPath = (Get-Item -LiteralPath $analysisPath).FullName
        Error = $errorMessage
    }
}

$indexPath = Join-Path $analysisRoot "index.json"
@{
    timestamp = (Get-Date).ToString("o")
    inventoryPath = if ($FromInventory) { (Resolve-ProjectPath $InventoryPath) } else { $null }
    generatedProgramPrefixes = @($generatedProgramPrefixes)
    includeGeneratedPrograms = -not [bool]$ExcludeGeneratedPrograms
    excludeGeneratedPrograms = [bool]$ExcludeGeneratedPrograms
    includeAiPrograms = -not [bool]$ExcludeGeneratedPrograms
    excludeAiPrograms = [bool]$ExcludeGeneratedPrograms
    resultCount = @($results).Count
    results = @($results)
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $indexPath -Encoding ASCII

$results
