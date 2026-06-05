param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,31}$')]
    [string]$ProgramName,

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

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $projectRoot $Path
}

if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $resolvedOutputRoot = $OutputRoot
} else {
    $resolvedOutputRoot = Join-Path $projectRoot $OutputRoot
}

function Invoke-FtpScript {
    param(
        [string[]]$Commands,
        [string]$RobotIp
    )

    $ftpScript = Join-Path $env:TEMP ("fanuc-readback-{0}.ftp" -f ([Guid]::NewGuid().ToString("N")))
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

$program = $ProgramName.ToUpperInvariant()
$jobDir = Join-Path (Join-Path $resolvedOutputRoot "jobs") $program
$localCompiledPath = Join-Path (Join-Path $resolvedOutputRoot "compiled") ($program + ".TP")
$readbackDir = Join-Path $jobDir "upload-readback"
$readbackTpPath = Join-Path $readbackDir ($program + ".TP")
$readbackLsPath = Join-Path $readbackDir ($program + ".LS")
$reportPath = Join-Path $jobDir "upload-readback.json"

if (-not (Test-Path -LiteralPath $localCompiledPath)) {
    throw "Local compiled TP not found: $localCompiledPath"
}

foreach ($path in @($jobDir, $readbackDir)) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

foreach ($path in @($readbackTpPath, $readbackLsPath, $reportPath)) {
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        throw "Readback output already exists: $path. Use -Force to overwrite."
    }
}

foreach ($path in @($readbackTpPath, $readbackLsPath)) {
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Force
    }
}

$remoteName = $program + ".TP"
$download = Invoke-FtpScript -RobotIp $config.RobotIp -Commands @(
    "user $($config.UserName) $($config.Password)",
    "binary",
    "get $remoteName `"$readbackTpPath`"",
    "quit"
)

$ftpText = $download.Output -join "`n"
if ($download.ExitCode -ne 0 -or $ftpText -match '(?im)^550\s') {
    throw "FTP readback failed:`n$ftpText"
}

if (-not (Test-Path -LiteralPath $readbackTpPath)) {
    throw "FTP completed but readback TP was not created: $readbackTpPath"
}

$printTpPath = Join-Path (Split-Path -Parent $config.MakeTpPath) "printtp.exe"
if (-not (Test-Path -LiteralPath $printTpPath)) {
    throw "PrintTP not found: $printTpPath"
}

$robotIniPath = Resolve-ProjectPath $config.RobotIniPath
$printTpOutput = & $printTpPath $readbackTpPath $readbackLsPath /config $robotIniPath /ver $config.WinOlpcVersion 2>&1
$printTpExitCode = $LASTEXITCODE
$decodeSucceeded = ($printTpExitCode -eq 0 -and (Test-Path -LiteralPath $readbackLsPath))

$localHash = (Get-FileHash -LiteralPath $localCompiledPath -Algorithm SHA256).Hash
$readbackHash = (Get-FileHash -LiteralPath $readbackTpPath -Algorithm SHA256).Hash
$hashMatch = ($localHash -eq $readbackHash)

$report = [ordered]@{
    timestamp = (Get-Date).ToString("o")
    programName = $program
    localCompiledPath = (Get-Item -LiteralPath $localCompiledPath).FullName
    readbackTpPath = (Get-Item -LiteralPath $readbackTpPath).FullName
    readbackLsPath = if (Test-Path -LiteralPath $readbackLsPath) { (Get-Item -LiteralPath $readbackLsPath).FullName } else { $null }
    localCompiledSha256 = $localHash
    readbackSha256 = $readbackHash
    hashMatch = $hashMatch
    decodeSucceeded = $decodeSucceeded
    printTpExitCode = $printTpExitCode
    ftpOutput = @($download.Output)
    printTpOutput = @($printTpOutput)
}

$report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding ASCII

if (-not $hashMatch) {
    throw "Robot readback TP hash does not match local compiled TP. See $reportPath"
}

if (-not $decodeSucceeded) {
    throw "Robot readback TP hash matched local compiled TP, but PrintTP could not decode the readback copy. See $reportPath"
}

[pscustomobject]@{
    ProgramName = $program
    HashMatch = $hashMatch
    DecodeSucceeded = $decodeSucceeded
    ReportPath = (Get-Item -LiteralPath $reportPath).FullName
    ReadbackTpPath = (Get-Item -LiteralPath $readbackTpPath).FullName
}
