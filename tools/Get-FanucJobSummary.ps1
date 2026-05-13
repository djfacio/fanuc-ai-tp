param(
    [switch]$IncludeRobot,
    [switch]$UseLatestRobotInventory,
    [string]$RobotInventoryPath,
    [string]$Pattern = "AI_*.TP",
    [string]$ConfigPath = "..\config\robot.psd1"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$jobsRoot = Join-Path $projectRoot "generated\jobs"

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $projectRoot $Path
}

$robotByProgram = @{}
$robotLookupStatus = if ($IncludeRobot -or $UseLatestRobotInventory -or $RobotInventoryPath) { "not-run" } else { "not-requested" }
$robotLookupError = $null
$robotLookupRequested = ($IncludeRobot -or $UseLatestRobotInventory -or [bool]$RobotInventoryPath)
if ($UseLatestRobotInventory -and -not $RobotInventoryPath) {
    $RobotInventoryPath = "generated\robot-inventory\latest.json"
}

if ($RobotInventoryPath) {
    $resolvedInventoryPath = Resolve-ProjectPath $RobotInventoryPath
    try {
        if (-not (Test-Path -LiteralPath $resolvedInventoryPath)) {
            throw "Robot inventory snapshot not found: $resolvedInventoryPath"
        }
        $inventory = Get-Content -LiteralPath $resolvedInventoryPath -Raw | ConvertFrom-Json
        foreach ($file in @($inventory.entries)) {
            if ($file.ProgramName -and $file.Extension -eq ".TP") {
                $robotByProgram[$file.ProgramName] = $file
            }
        }
        $robotLookupStatus = "snapshot"
    } catch {
        $robotLookupStatus = "unavailable"
        $robotLookupError = $_.Exception.Message
        Write-Warning $robotLookupError
    }
} elseif ($IncludeRobot) {
    $directoryTool = Join-Path $scriptRoot "Get-FanucRobotDirectory.ps1"
    try {
        $robotFiles = & $directoryTool -Pattern $Pattern -ConfigPath $ConfigPath
        foreach ($file in @($robotFiles)) {
            if ($file.ProgramName) {
                $robotByProgram[$file.ProgramName] = $file
            }
        }
        $robotLookupStatus = "ok"
    } catch {
        $robotLookupStatus = "unavailable"
        $robotLookupError = $_.Exception.Message
        Write-Warning $robotLookupError
    }
}

if (-not (Test-Path -LiteralPath $jobsRoot)) {
    return
}

$manifests = Get-ChildItem -LiteralPath $jobsRoot -Directory |
    ForEach-Object {
        $manifestPath = Join-Path $_.FullName "manifest.json"
        if (Test-Path -LiteralPath $manifestPath) {
            [pscustomobject]@{
                JobDir = $_.FullName
                ManifestPath = $manifestPath
                Manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
            }
        }
    }

$records = foreach ($entry in $manifests) {
    $manifest = $entry.Manifest
    $program = if ($manifest.programName) { $manifest.programName.ToUpperInvariant() } else { (Split-Path -Leaf $entry.JobDir).ToUpperInvariant() }
    $readbackPath = Join-Path $entry.JobDir "upload-readback.json"
    $readback = if (Test-Path -LiteralPath $readbackPath) {
        Get-Content -LiteralPath $readbackPath -Raw | ConvertFrom-Json
    } else {
        $null
    }
    $robotFile = if ($robotByProgram.ContainsKey($program)) { $robotByProgram[$program] } else { $null }

    [pscustomobject]@{
        ProgramName = $program
        LocalEvidencePassed = if ($manifest.gates) { [bool]$manifest.gates.localEvidencePassed } else { $false }
        ReadyForUpload = if ($manifest.gates) { [bool]$manifest.gates.readyForUpload } else { $false }
        HumanReviewStatus = if ($manifest.humanReview) { $manifest.humanReview.status } else { "not-recorded" }
        UploadStatus = if ($manifest.upload) { $manifest.upload.status } else { "not-recorded" }
        ReadbackHashMatch = if ($null -ne $readback) { [bool]$readback.hashMatch } else { $false }
        ReadbackDecodeSucceeded = if ($null -ne $readback) { [bool]$readback.decodeSucceeded } else { $false }
        RobotLookupStatus = $robotLookupStatus
        RobotFilePresent = if ($robotLookupRequested) { $null -ne $robotFile } else { $null }
        RobotFileName = if ($null -ne $robotFile) { $robotFile.Name } else { $null }
        RobotFileSize = if ($null -ne $robotFile) { $robotFile.Size } else { $null }
        RobotLookupError = $robotLookupError
        ManifestPath = $entry.ManifestPath
    }
}

$records | Sort-Object ProgramName
