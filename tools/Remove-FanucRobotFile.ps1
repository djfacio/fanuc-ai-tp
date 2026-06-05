param(
    [Parameter(Mandatory = $true)]
    [string]$RemoteName,

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

if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $resolvedOutputRoot = $OutputRoot
} else {
    $resolvedOutputRoot = Join-Path $projectRoot $OutputRoot
}

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig
$targetName = $RemoteName.ToUpperInvariant()

if ($targetName -cnotmatch '^[A-Z][A-Z0-9_]{0,31}\.(PC|TP)$') {
    throw "RemoteName must be an uppercase FANUC program file name ending in .PC or .TP."
}

if (-not $Force) {
    throw "Deleting robot files requires -Force: $targetName"
}

function Invoke-FtpScript {
    param(
        [string[]]$Commands,
        [string]$RobotIp
    )

    $ftpScript = Join-Path $env:TEMP ("fanuc-remove-file-{0}.ftp" -f ([Guid]::NewGuid().ToString("N")))
    try {
        Set-Content -LiteralPath $ftpScript -Value $Commands -Encoding ASCII
        $output = & ftp.exe -n -s:$ftpScript $RobotIp 2>&1
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = @($output)
        }
    }
    finally {
        if (Test-Path -LiteralPath $ftpScript) {
            Remove-Item -LiteralPath $ftpScript -Force
        }
    }
}

$deleteResult = Invoke-FtpScript -RobotIp $config.RobotIp -Commands @(
    "user $($config.UserName) $($config.Password)",
    "binary",
    "delete $targetName",
    "dir $targetName",
    "quit"
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logsDir = Join-Path $resolvedOutputRoot "logs"
if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$logPath = Join-Path $logsDir ("delete-$($targetName.Replace('.', '-'))-$timestamp.log")
Set-Content -LiteralPath $logPath -Value $deleteResult.Output -Encoding ASCII

$ftpText = $deleteResult.Output -join "`n"
if ($deleteResult.ExitCode -ne 0 -or $ftpText -match '(?im)^(45\d)\s') {
    throw "FTP delete failed. See $logPath"
}

$deleted = ($ftpText -match '(?im)^250\s')
$stillPresent = ($ftpText -match "(?im)^-.+\s$([regex]::Escape($targetName.ToLowerInvariant()))\s*$")

if (-not $deleted -or $stillPresent) {
    throw "Robot file delete was not confirmed for $targetName. See $logPath"
}

[pscustomobject]@{
    RemoteName = $targetName
    RobotIp = $config.RobotIp
    Deleted = $true
    LogPath = (Get-Item -LiteralPath $logPath).FullName
}
