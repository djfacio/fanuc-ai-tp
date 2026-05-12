param(
    [string]$Pattern = "*",
    [string]$OutputRoot = "generated\robot-inventory",
    [string]$ConfigPath = "..\config\robot.psd1"
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

if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $resolvedOutputRoot = $OutputRoot
} else {
    $resolvedOutputRoot = Join-Path $projectRoot $OutputRoot
}

$timestamp = Get-Date
$stamp = $timestamp.ToString("yyyyMMdd-HHmmss")
$snapshotDir = Join-Path $resolvedOutputRoot $stamp
$snapshotPath = Join-Path $snapshotDir "md-listing.json"
$latestPath = Join-Path $resolvedOutputRoot "latest.json"

if (-not (Test-Path -LiteralPath $snapshotDir)) {
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
}

$directoryTool = Join-Path $scriptRoot "Get-FanucRobotDirectory.ps1"
$entries = @(& $directoryTool -Pattern $Pattern -ConfigPath $resolvedConfig)

$inventory = [ordered]@{
    schemaVersion = 1
    timestamp = $timestamp.ToString("o")
    robotIp = $config.RobotIp
    device = "MD:"
    pattern = $Pattern
    entryCount = $entries.Count
    entries = @($entries | Sort-Object ProgramName, Name)
}

$inventory | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $snapshotPath -Encoding ASCII
$inventory | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestPath -Encoding ASCII

[pscustomobject]@{
    Timestamp = $inventory.timestamp
    RobotIp = $inventory.robotIp
    EntryCount = $inventory.entryCount
    SnapshotPath = (Get-Item -LiteralPath $snapshotPath).FullName
    LatestPath = (Get-Item -LiteralPath $latestPath).FullName
}
