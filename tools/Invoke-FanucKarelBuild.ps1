param(
    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [string]$OutputDir = "generated\karel",
    [string]$RobotConfigPath = "config\robot.psd1",
    [string]$KtransPath,
    [string]$RobotIniPath,
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

$resolvedSource = Resolve-Path -LiteralPath (Resolve-ProjectPath $SourcePath)
$sourceText = Get-Content -LiteralPath $resolvedSource -Raw
$programMatch = [regex]::Match($sourceText, '(?im)^\s*PROGRAM\s+([A-Z][A-Z0-9_]{1,30})\s*$')
if (-not $programMatch.Success) {
    throw "KAREL source does not contain a PROGRAM header: $($resolvedSource.Path)"
}

$programName = $programMatch.Groups[1].Value.ToUpperInvariant()
if ($programName -notmatch '^A_[A-Z0-9_]{1,30}$') {
    throw "KAREL program '$programName' must use the generated A_ prefix."
}

$resolvedRobotConfig = Resolve-ProjectPath $RobotConfigPath
if (-not $KtransPath -or -not $RobotIniPath) {
    $robotConfig = Import-PowerShellDataFile -LiteralPath $resolvedRobotConfig
    if (-not $KtransPath) {
        if (-not $robotConfig.MakeTpPath) {
            throw "Robot config does not define MakeTpPath; pass -KtransPath explicitly."
        }
        $KtransPath = Join-Path (Split-Path -Parent $robotConfig.MakeTpPath) "ktrans.exe"
    }
    if (-not $RobotIniPath) {
        $RobotIniPath = $robotConfig.RobotIniPath
    }
}

$resolvedKtrans = Resolve-Path -LiteralPath $KtransPath
$resolvedRobotIni = Resolve-Path -LiteralPath (Resolve-ProjectPath $RobotIniPath)
$resolvedOutputDir = Resolve-ProjectPath $OutputDir
if (-not (Test-Path -LiteralPath $resolvedOutputDir)) {
    New-Item -ItemType Directory -Path $resolvedOutputDir -Force | Out-Null
}

$buildDir = Join-Path $resolvedOutputDir "_build"
if (-not (Test-Path -LiteralPath $buildDir)) {
    New-Item -ItemType Directory -Path $buildDir -Force | Out-Null
}

$pcOutput = Join-Path $resolvedOutputDir "$programName.PC"
$lsOutput = Join-Path $resolvedOutputDir "$programName.LS"
if (((Test-Path -LiteralPath $pcOutput) -or (Test-Path -LiteralPath $lsOutput)) -and -not $Force) {
    throw "KAREL outputs already exist for $programName in $resolvedOutputDir. Use -Force to overwrite."
}

Push-Location $buildDir
try {
    $output = & $resolvedKtrans.Path /l $resolvedSource.Path /config $resolvedRobotIni.Path 2>&1
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($exitCode -ne 0) {
    throw "KTRANS failed for $($resolvedSource.Path) with exit code $exitCode.`n$($output -join "`n")"
}

$lowerBase = $programName.ToLowerInvariant()
$builtPc = Join-Path $buildDir "$lowerBase.pc"
$builtLs = Join-Path $buildDir "$lowerBase.LS"
if (-not (Test-Path -LiteralPath $builtPc)) {
    throw "KTRANS reported success but did not produce $builtPc."
}
if (-not (Test-Path -LiteralPath $builtLs)) {
    throw "KTRANS reported success but did not produce $builtLs."
}

Copy-Item -LiteralPath $builtPc -Destination $pcOutput -Force
Copy-Item -LiteralPath $builtLs -Destination $lsOutput -Force

[pscustomobject]@{
    ProgramName = $programName
    SourcePath = (Get-Item -LiteralPath $resolvedSource).FullName
    PcPath = (Get-Item -LiteralPath $pcOutput).FullName
    ListingPath = (Get-Item -LiteralPath $lsOutput).FullName
    KtransPath = (Get-Item -LiteralPath $resolvedKtrans).FullName
    RobotIniPath = (Get-Item -LiteralPath $resolvedRobotIni).FullName
}
