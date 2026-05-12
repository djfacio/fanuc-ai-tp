param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9_\-]+(\.TP)?$')]
    [string]$Program,

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

function Resolve-ProjectPath {
    param(
        [string]$Path
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $projectRoot $Path
}

$baseName = [System.IO.Path]::GetFileNameWithoutExtension($Program).ToUpperInvariant()
$remoteName = $baseName + ".TP"
$tpDir = Join-Path $projectRoot "downloaded\tp"
$lsDir = Join-Path $projectRoot "downloaded\ls"
$tpPath = Join-Path $tpDir $remoteName
$lsPath = Join-Path $lsDir ($baseName + ".LS")
$robotIniPath = Resolve-ProjectPath $config.RobotIniPath
$workcellLsPath = Join-Path $config.WorkcellRobotPath ("output\" + $baseName + ".LS")

if ((Test-Path -LiteralPath $tpPath) -and -not $Force) {
    throw "Downloaded TP already exists: $tpPath. Use -Force to overwrite."
}

if ((Test-Path -LiteralPath $lsPath) -and -not $Force) {
    throw "Decoded LS already exists: $lsPath. Use -Force to overwrite."
}

if (Test-Path -LiteralPath $tpPath) {
    Remove-Item -LiteralPath $tpPath -Force
}

if (Test-Path -LiteralPath $lsPath) {
    Remove-Item -LiteralPath $lsPath -Force
}

if (Test-Path -LiteralPath $workcellLsPath) {
    Remove-Item -LiteralPath $workcellLsPath -Force
}

$ftpScript = Join-Path $env:TEMP ("fanuc-read-tp-{0}.ftp" -f ([Guid]::NewGuid().ToString("N")))
try {
    Set-Content -LiteralPath $ftpScript -Encoding ASCII -Value @(
        "user $($config.UserName) $($config.Password)",
        "binary",
        "get $remoteName `"$tpPath`"",
        "quit"
    )

    Write-Host "Downloading $remoteName from $($config.RobotIp)"
    $ftpOutput = & ftp.exe -n -s:$ftpScript $config.RobotIp 2>&1
    $ftpText = $ftpOutput -join "`n"
    if ($LASTEXITCODE -ne 0 -or $ftpText -match '(?im)^550\s') {
        throw "FTP download failed:`n$ftpText"
    }
}
finally {
    if (Test-Path -LiteralPath $ftpScript) {
        Remove-Item -LiteralPath $ftpScript -Force
    }
}

if (-not (Test-Path -LiteralPath $tpPath)) {
    throw "FTP completed but local TP file was not created: $tpPath"
}

Write-Host "Downloaded $tpPath"

if (-not (Test-Path -LiteralPath $config.MakeTpPath)) {
    throw "PrintTP/MakeTP folder not found via MakeTpPath: $($config.MakeTpPath)"
}

$printTpPath = Join-Path (Split-Path -Parent $config.MakeTpPath) "printtp.exe"
if (-not (Test-Path -LiteralPath $printTpPath)) {
    throw "PrintTP not found: $printTpPath"
}

Write-Host "Decoding $remoteName to LS"
& $printTpPath $tpPath $lsPath /config $robotIniPath /ver $config.WinOlpcVersion

if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $workcellLsPath)) {
    throw "PrintTP failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $lsPath) -and (Test-Path -LiteralPath $workcellLsPath)) {
    Copy-Item -LiteralPath $workcellLsPath -Destination $lsPath -Force
}

if (-not (Test-Path -LiteralPath $lsPath)) {
    throw "PrintTP completed but decoded LS was not created: $lsPath"
}

Write-Host "Decoded $lsPath"
Get-Item -LiteralPath $lsPath
