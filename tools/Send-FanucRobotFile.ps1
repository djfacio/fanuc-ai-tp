param(
    [Parameter(Mandatory = $true)]
    [string]$LocalPath,

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
$resolvedLocal = Resolve-Path -LiteralPath $LocalPath
$localItem = Get-Item -LiteralPath $resolvedLocal
$extension = $localItem.Extension.ToUpperInvariant()

if ($extension -notin @(".PC", ".TP")) {
    throw "Only reviewed FANUC .PC and .TP files can be uploaded with this helper: $($localItem.FullName)"
}

$targetName = if ($RemoteName) {
    $RemoteName.ToUpperInvariant()
} else {
    $localItem.Name.ToUpperInvariant()
}

if ($targetName -cnotmatch '^[A-Z][A-Z0-9_]{0,31}\.(PC|TP)$') {
    throw "RemoteName must be an uppercase FANUC program file name ending in .PC or .TP."
}

function Invoke-FtpScript {
    param(
        [string[]]$Commands,
        [string]$RobotIp
    )

    $ftpScript = Join-Path $env:TEMP ("fanuc-send-file-{0}.ftp" -f ([Guid]::NewGuid().ToString("N")))
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

function Test-RemoteFile {
    param([string]$Name)

    $result = Invoke-FtpScript -RobotIp $config.RobotIp -Commands @(
        "user $($config.UserName) $($config.Password)",
        "binary",
        "dir $Name",
        "quit"
    )

    return (($result.Output -join "`n") -match "(?im)\s$([regex]::Escape($Name.ToLowerInvariant()))\s*$")
}

if ((Test-RemoteFile -Name $targetName) -and -not $Force) {
    throw "Remote file already exists on robot: $targetName. Use -Force to overwrite."
}

$uploadResult = Invoke-FtpScript -RobotIp $config.RobotIp -Commands @(
    "user $($config.UserName) $($config.Password)",
    "binary",
    "put `"$($localItem.FullName)`" $targetName",
    "dir $targetName",
    "quit"
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logsDir = Join-Path $resolvedOutputRoot "logs"
if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}

$logPath = Join-Path $logsDir ("upload-$($localItem.BaseName.ToUpperInvariant())-$timestamp.log")
Set-Content -LiteralPath $logPath -Value $uploadResult.Output -Encoding ASCII

$ftpText = $uploadResult.Output -join "`n"
if ($uploadResult.ExitCode -ne 0 -or $ftpText -match '(?im)^(45\d|55\d)\s') {
    throw "FTP upload failed. See $logPath"
}

[pscustomobject]@{
    LocalPath = $localItem.FullName
    RemoteName = $targetName
    RobotIp = $config.RobotIp
    Uploaded = $true
    LogPath = (Get-Item -LiteralPath $logPath).FullName
}
