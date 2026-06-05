param(
    [string]$OutputPath = "config\robot.local.psd1",
    [string]$RobotIp = "192.0.2.10",
    [string]$UserName = "anonymous",
    [string]$Password = "guest",
    [string]$MakeTpPath = "",
    [string]$WorkcellRobotPath = "",
    [string]$RobotIniPath = "",
    [string]$CellMapPath = "config\cell-map.psd1",
    [string]$ProgramPrefix = "A_",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

function Resolve-OutputPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $projectRoot $Path
}

function Find-MakeTp {
    $candidates = @(
        "C:\Program Files (x86)\FANUC\WinOLPC\bin\maketp.exe",
        "C:\Program Files\FANUC\WinOLPC\bin\maketp.exe"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }

    $versionRoots = @(
        "C:\Program Files (x86)\FANUC\WinOLPC\Versions",
        "C:\Program Files\FANUC\WinOLPC\Versions"
    )

    foreach ($root in $versionRoots) {
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }

        $found = Get-ChildItem -LiteralPath $root -Recurse -Filter "maketp.exe" -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1
        if ($found) {
            return $found.FullName
        }
    }

    return ""
}

function Find-RoboguideRobotPath {
    $myWorkcells = Join-Path ([Environment]::GetFolderPath("MyDocuments")) "My Workcells"
    if (-not (Test-Path -LiteralPath $myWorkcells)) {
        return ""
    }

    $found = Get-ChildItem -LiteralPath $myWorkcells -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^Robot_\d+$' -and
            (Test-Path -LiteralPath (Join-Path $_.FullName "support")) -and
            (Test-Path -LiteralPath (Join-Path $_.FullName "output"))
        } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if ($found) {
        return $found.FullName
    }

    return ""
}

function Get-WinOlpcVersion {
    param([string]$Path)

    if (-not $Path) {
        return ""
    }

    $match = [regex]::Match($Path, 'Versions\\([^\\]+)\\bin\\maketp\.exe$', 'IgnoreCase')
    if ($match.Success) {
        return $match.Groups[1].Value
    }

    return ""
}

function Test-UsableRobotIni {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $false
    }

    $text = Get-Content -LiteralPath $Path -Raw
    return ($text -notmatch 'REVIEW_AND_SET')
}

$resolvedOutputPath = Resolve-OutputPath -Path $OutputPath
if ((Test-Path -LiteralPath $resolvedOutputPath) -and -not $Force) {
    throw "Robot config already exists: $resolvedOutputPath. Use -Force to overwrite."
}

if (-not $MakeTpPath) {
    $MakeTpPath = Find-MakeTp
}

if (-not $WorkcellRobotPath) {
    $WorkcellRobotPath = Find-RoboguideRobotPath
}

if (-not $RobotIniPath) {
    $outputDir = Split-Path -Parent $resolvedOutputPath
    $localRobotIni = Join-Path $outputDir "robot.ini"
    $repoRobotIni = Join-Path $projectRoot "config\robot.ini"

    if (Test-UsableRobotIni -Path $localRobotIni) {
        $RobotIniPath = "robot.ini"
    } elseif (Test-UsableRobotIni -Path $repoRobotIni) {
        $RobotIniPath = "config\robot.ini"
    } else {
        $RobotIniPath = "REVIEW_AND_SET_ROBOT_INI_PATH"
    }
}

$winOlpcVersion = Get-WinOlpcVersion -Path $MakeTpPath
if (-not $winOlpcVersion) {
    $winOlpcVersion = "REVIEW_AND_SET_WINOLPC_VERSION"
}

if (-not $MakeTpPath) {
    $MakeTpPath = "REVIEW_AND_SET_MAKETP_PATH"
}

if (-not $WorkcellRobotPath) {
    $WorkcellRobotPath = "REVIEW_AND_SET_ROBOGUIDE_WORKCELL_ROBOT_PATH"
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$content = @"
@{
    RobotIp = "$RobotIp"
    UserName = "$UserName"
    Password = "$Password"
    WinOlpcVersion = "$winOlpcVersion"
    MakeTpPath = "$MakeTpPath"
    RobotIniPath = "$RobotIniPath"
    CellMapPath = "$CellMapPath"
    WorkcellRobotPath = "$WorkcellRobotPath"
    ProgramPrefix = "$ProgramPrefix"
    LegacyProgramPrefixes = @("AI_")
    KnownMacroPrograms = @()
    CleanupProtectedPrograms = @(
        "-BCKEDT-"
    )
}
"@

Set-Content -LiteralPath $resolvedOutputPath -Value $content -Encoding ASCII

[pscustomobject]@{
    Path = $resolvedOutputPath
    RobotIp = $RobotIp
    MakeTpPath = $MakeTpPath
    WinOlpcVersion = $winOlpcVersion
    WorkcellRobotPath = $WorkcellRobotPath
    RobotIniPath = $RobotIniPath
}
