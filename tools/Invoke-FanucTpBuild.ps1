param(
    [Parameter(Mandatory = $true)]
    [string]$LsPath,

    [string]$ConfigPath = "..\config\robot.psd1",
    [string]$OutputRoot = "generated",
    [switch]$Upload,
    [switch]$UploadOnlyStaging,
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
    param(
        [string]$Path
    )

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

function Invoke-FtpScript {
    param(
        [string[]]$Commands,
        [string]$RobotIp
    )

    $ftpScript = Join-Path $env:TEMP ("fanuc-ai-tp-{0}.ftp" -f ([Guid]::NewGuid().ToString("N")))
    try {
        Set-Content -LiteralPath $ftpScript -Value $Commands -Encoding ASCII
        $output = & ftp.exe -n -s:$ftpScript $RobotIp 2>&1
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = $output
        }
    }
    finally {
        if (Test-Path -LiteralPath $ftpScript) {
            Remove-Item -LiteralPath $ftpScript -Force
        }
    }
}

function Test-RemoteFile {
    param(
        [string]$RemoteName
    )

    $result = Invoke-FtpScript -RobotIp $config.RobotIp -Commands @(
        "user $($config.UserName) $($config.Password)",
        "binary",
        "dir $RemoteName",
        "quit"
    )

    return (($result.Output -join "`n") -match "(?im)\s$([regex]::Escape($RemoteName.ToLowerInvariant()))\s*$")
}

$resolvedLs = Resolve-Path -LiteralPath $LsPath
$lsItem = Get-Item -LiteralPath $resolvedLs
$programName = $lsItem.BaseName.ToUpperInvariant()
$safetyTool = Join-Path $scriptRoot "Test-FanucLsSafety.ps1"
& $safetyTool -LsPath $lsItem.FullName -ProgramName $programName -ConfigPath $resolvedConfig -Quiet

$manifestPath = Join-Path (Join-Path $resolvedOutputRoot "jobs") (Join-Path $programName "manifest.json")
if ($Upload -and (Test-Path -LiteralPath $manifestPath)) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if (-not [bool]$manifest.gates.readyForUpload) {
        if (-not $UploadOnlyStaging) {
            throw "Job manifest is not ready for upload: $manifestPath. Record human review with Set-FanucJobStatus.ps1 after local evidence is reviewed."
        }

        $requiredStageGatesPassed = (
            [bool]$manifest.gates.specValidationPassed -and
            [bool]$manifest.gates.lsSafetyPassed -and
            [bool]$manifest.gates.roundTripOverallMatch
        )

        if ($manifest.gates.PSObject.Properties.Name -contains "motionGeneratedLsPassed") {
            $requiredStageGatesPassed = ($requiredStageGatesPassed -and [bool]$manifest.gates.motionGeneratedLsPassed)
        }

        if (-not $requiredStageGatesPassed) {
            throw "Upload-only staging requires spec validation, LS safety, motion LS/spec match when applicable, and round-trip evidence to pass: $manifestPath"
        }

        if ($manifest.humanReview.status -ne "approved") {
            throw "Upload-only staging requires recorded human review approval: $manifestPath"
        }

        Write-Warning "Upload-only staging requested. Operator owns robot setup, path safety, and physical run decisions."
    }
}

if (-not (Test-Path -LiteralPath $config.MakeTpPath)) {
    throw "MakeTP not found: $($config.MakeTpPath)"
}

$robotIniPath = Resolve-ConfigOrProjectPath $config.RobotIniPath
$compiledDir = Join-Path $resolvedOutputRoot "compiled"
$tpPath = Join-Path $compiledDir ($programName + ".TP")
$workcellTpPath = Join-Path $config.WorkcellRobotPath ("output\" + $programName + ".TP")

if (-not (Test-Path -LiteralPath $compiledDir)) {
    New-Item -ItemType Directory -Path $compiledDir -Force | Out-Null
}

if ((Test-Path -LiteralPath $tpPath) -and -not $Force) {
    throw "Compiled output already exists: $tpPath. Use -Force to overwrite."
}

if (Test-Path -LiteralPath $tpPath) {
    Remove-Item -LiteralPath $tpPath -Force
}

if (Test-Path -LiteralPath $workcellTpPath) {
    Remove-Item -LiteralPath $workcellTpPath -Force
}

$makeTpLockPath = Join-Path $compiledDir ".maketp.lock"
$makeTpLock = $null
try {
    $deadline = (Get-Date).AddMinutes(2)
    while ($null -eq $makeTpLock) {
        try {
            $makeTpLock = [System.IO.File]::Open($makeTpLockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        } catch [System.IO.IOException] {
            if ((Get-Date) -ge $deadline) {
                throw "Timed out waiting for MakeTP compile lock: $makeTpLockPath"
            }
            Start-Sleep -Milliseconds 250
        }
    }

    Write-Host "Compiling $($lsItem.FullName)"
    if (Test-Path -LiteralPath $robotIniPath) {
        & $config.MakeTpPath $lsItem.FullName $tpPath /config $robotIniPath /ver $config.WinOlpcVersion
    } else {
        & $config.MakeTpPath $lsItem.FullName $tpPath /ver $config.WinOlpcVersion
    }
}
finally {
    if ($null -ne $makeTpLock) {
        $makeTpLock.Dispose()
    }
}

if ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $workcellTpPath)) {
    throw "MakeTP failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $tpPath) -and (Test-Path -LiteralPath $workcellTpPath)) {
    Copy-Item -LiteralPath $workcellTpPath -Destination $tpPath -Force
}

if (-not (Test-Path -LiteralPath $tpPath)) {
    throw "MakeTP completed but TP file was not created: $tpPath"
}

$jobDir = Join-Path (Join-Path $resolvedOutputRoot "jobs") $programName
if (Test-Path -LiteralPath $jobDir) {
    Copy-Item -LiteralPath $tpPath -Destination (Join-Path $jobDir ($programName + ".TP")) -Force
}

Write-Host "Created $tpPath"

if (-not $Upload) {
    Write-Host "Upload skipped. Re-run with -Upload to send the TP to robot MD:."
    return
}

$remoteName = $programName + ".TP"
if ((Test-RemoteFile -RemoteName $remoteName) -and -not $Force) {
    throw "Remote file already exists on robot: $remoteName. Use -Force to overwrite."
}

$uploadResult = Invoke-FtpScript -RobotIp $config.RobotIp -Commands @(
    "user $($config.UserName) $($config.Password)",
    "binary",
    "put `"$tpPath`" $remoteName",
    "dir $remoteName",
    "quit"
)

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$logsDir = Join-Path $resolvedOutputRoot "logs"
if (-not (Test-Path -LiteralPath $logsDir)) {
    New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
}
$logPath = Join-Path $logsDir ("upload-$programName-$timestamp.log")
Set-Content -LiteralPath $logPath -Value $uploadResult.Output -Encoding ASCII

if ($uploadResult.ExitCode -ne 0) {
    throw "FTP failed with exit code $($uploadResult.ExitCode). See $logPath"
}

$statusTool = Join-Path $scriptRoot "Set-FanucJobStatus.ps1"
if (Test-Path -LiteralPath $statusTool) {
    try {
        & $statusTool -ProgramName $programName -ConfigPath $resolvedConfig -OutputRoot $resolvedOutputRoot -UploadStatus uploaded -UploadLogPath $logPath | Out-Null
    } catch {
        Write-Warning "Upload succeeded, but job manifest upload status was not updated: $($_.Exception.Message)"
    }
}

if ($UploadOnlyStaging -and (Test-Path -LiteralPath $jobDir)) {
    $stagingPath = Join-Path $jobDir "upload-staging.json"
    [ordered]@{
        updatedAt = (Get-Date).ToString("o")
        programName = $programName
        status = "uploaded-for-staging-only"
        remoteName = $remoteName
        robotIp = $config.RobotIp
        uploadLogPath = $logPath
        notes = "Program was uploaded for staging only. Operator owns robot setup, PR data, path safety, and any physical pendant-side decisions."
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $stagingPath -Encoding ASCII
}

Write-Host "Uploaded $remoteName to $($config.RobotIp)"
Write-Host "Log: $logPath"
