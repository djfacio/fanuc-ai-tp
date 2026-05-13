param(
    [Parameter(Mandatory = $true)]
    [string]$DependencyMapPath,

    [string]$ConfigPath = "..\config\robot.psd1",

    [string]$OutputRoot = "generated\robot-cleanup",

    [switch]$Execute
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

function Resolve-RepoPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $projectRoot $Path
}

function Resolve-ScriptRelativePath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $scriptRoot $Path
}

function Invoke-FtpScript {
    param(
        [string[]]$Commands,
        [string]$RobotIp,
        [string]$LogPath
    )

    $ftpScript = Join-Path $env:TEMP ("fanuc-cleanup-{0}.ftp" -f ([Guid]::NewGuid().ToString("N")))
    try {
        Set-Content -LiteralPath $ftpScript -Value $Commands -Encoding ASCII
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = & ftp.exe -n -s:$ftpScript $RobotIp 2>&1
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }

        if ($LogPath) {
            Set-Content -LiteralPath $LogPath -Value $output -Encoding UTF8
        }

        [pscustomobject]@{
            ExitCode = $exitCode
            Output = @($output)
        }
    }
    finally {
        if (Test-Path -LiteralPath $ftpScript) {
            Remove-Item -LiteralPath $ftpScript -Force
        }
    }
}

function Assert-FtpSuccess {
    param(
        [object]$Result,
        [string]$Operation,
        [switch]$AllowFileErrors
    )

    $ftpText = $Result.Output -join "`n"
    if (
        $Result.ExitCode -ne 0 -or
        $ftpText -match '(?i)connect\s*:' -or
        $ftpText -match '(?i)not connected' -or
        $ftpText -match '(?i)login failed' -or
        $ftpText -match '(?i)unknown host' -or
        (($ftpText -match '(?im)^550\s') -and -not $AllowFileErrors)
    ) {
        throw "$Operation failed:`n$ftpText"
    }
}

function Get-DeleteResults {
    param(
        [object[]]$Output,
        [object[]]$Candidates
    )

    $byRobotName = @{}
    foreach ($candidate in $Candidates) {
        $byRobotName[[string]$candidate.robotName] = $candidate
    }

    $results = New-Object System.Collections.Generic.List[object]
    $pendingName = $null
    foreach ($line in @($Output)) {
        $text = [string]$line
        if ($text -match '^ftp>\s+delete\s+(.+)$') {
            $pendingName = $matches[1].Trim()
            continue
        }

        if (-not $pendingName) {
            continue
        }

        if ($text -match '^250\s+(.+)$') {
            $candidate = $byRobotName[$pendingName]
            $results.Add([pscustomobject]@{
                programName = $candidate.programName
                robotName = $pendingName
                status = "deleted"
                message = $matches[1].Trim()
            })
            $pendingName = $null
        } elseif ($text -match '^550\s+(.+)$') {
            $candidate = $byRobotName[$pendingName]
            $results.Add([pscustomobject]@{
                programName = $candidate.programName
                robotName = $pendingName
                status = "failed"
                message = $matches[1].Trim()
            })
            $pendingName = $null
        }
    }

    $results.ToArray()
}

$resolvedConfig = Resolve-ScriptRelativePath $ConfigPath
$resolvedDependencyMap = Resolve-RepoPath $DependencyMapPath

if (-not (Test-Path -LiteralPath $resolvedDependencyMap)) {
    throw "Dependency map not found: $resolvedDependencyMap"
}

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig
$map = Get-Content -Raw -LiteralPath $resolvedDependencyMap | ConvertFrom-Json

if ([int]$map.missingDependencyCount -ne 0) {
    throw "Refusing cleanup because dependency map reports missing dependencies: $($map.missingDependencyCount)"
}

if ([int]$map.dynamicReferenceCount -ne 0) {
    throw "Refusing cleanup because dependency map reports dynamic references: $($map.dynamicReferenceCount)"
}

$rootProgram = [string]$map.rootProgram
$requiredSet = @{}
foreach ($program in @($map.requiredPrograms)) {
    $requiredSet[[string]$program.programName] = $true
}

$knownMacroSet = @{}
foreach ($program in @($map.knownMacroPrograms)) {
    $knownMacroSet[[string]$program.programName] = $true
}

$candidates = @(
    $map.backupDeleteCandidates |
        Where-Object { [string]$_.robotName -match '(?i)\.tp$' } |
        Sort-Object programName
)

if ($candidates.Count -eq 0) {
    Write-Host "No TP non-dependency candidates found."
    return
}

foreach ($candidate in $candidates) {
    $programName = [string]$candidate.programName
    $robotName = [string]$candidate.robotName

    if ($requiredSet.ContainsKey($programName)) {
        throw "Refusing cleanup because candidate is required by ${rootProgram}: $programName"
    }

    if ($knownMacroSet.ContainsKey($programName)) {
        throw "Refusing cleanup because candidate is a configured macro program: $programName"
    }

    if ($robotName -notmatch '^[A-Za-z0-9_\-]+\.tp$') {
        throw "Refusing cleanup because robot file name is outside the expected TP pattern: $robotName"
    }
}

$originalCandidateCount = $candidates.Count
$directoryTool = Join-Path $scriptRoot "Get-FanucRobotDirectory.ps1"
$robotFiles = @(& $directoryTool -Pattern "*.TP" -ConfigPath $resolvedConfig)
$robotNameSet = @{}
foreach ($robotFile in $robotFiles) {
    $robotNameSet[[string]$robotFile.Name] = $true
}

$missingCandidates = @($candidates | Where-Object { -not $robotNameSet.ContainsKey([string]$_.robotName) })
$candidates = @($candidates | Where-Object { $robotNameSet.ContainsKey([string]$_.robotName) })

if ($candidates.Count -eq 0) {
    Write-Host "No listed TP non-dependency candidates are currently present on the robot."
    [pscustomobject]@{
        RootProgram = $rootProgram
        OriginalCandidateCount = $originalCandidateCount
        PresentCandidateCount = 0
        AlreadyMissingCount = $missingCandidates.Count
        Deleted = $false
    }
    return
}

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runRoot = Resolve-RepoPath (Join-Path $OutputRoot ("{0}-{1}" -f $timestamp, $rootProgram))
$backupRoot = Join-Path $runRoot "backup-tp"
New-Item -ItemType Directory -Force -Path $backupRoot | Out-Null

$planPath = Join-Path $runRoot "delete-plan.json"
$summaryPath = Join-Path $runRoot "delete-plan.md"
$backupLogPath = Join-Path $runRoot "ftp-backup.log"
$deleteLogPath = Join-Path $runRoot "ftp-delete.log"
$deleteResultsPath = Join-Path $runRoot "delete-results.json"

$plan = [pscustomobject]@{
    rootProgram = $rootProgram
    robotIp = $config.RobotIp
    sourceDependencyMap = (Resolve-Path -LiteralPath $resolvedDependencyMap).Path
    execute = [bool]$Execute
    originalCandidateCount = $originalCandidateCount
    presentCandidateCount = $candidates.Count
    alreadyMissingCount = $missingCandidates.Count
    backupRoot = $backupRoot
    candidates = @($candidates | ForEach-Object {
        [pscustomobject]@{
            programName = $_.programName
            robotName = $_.robotName
            size = $_.size
            reason = $_.reason
        }
    })
    alreadyMissingCandidates = @($missingCandidates | ForEach-Object {
        [pscustomobject]@{
            programName = $_.programName
            robotName = $_.robotName
            reason = "Listed in source dependency map, but not present on robot during cleanup run."
        }
    })
}
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# FANUC TP Non-Dependency Cleanup: $rootProgram")
$lines.Add("")
$lines.Add("- Robot IP: $($config.RobotIp)")
$lines.Add("- Source dependency map: $resolvedDependencyMap")
$lines.Add("- Source candidate count: $originalCandidateCount")
$lines.Add("- Present candidate count: $($candidates.Count)")
$lines.Add("- Already missing count: $($missingCandidates.Count)")
$lines.Add("- Execute delete: $([bool]$Execute)")
$lines.Add("- Backup folder: $backupRoot")
$lines.Add("")
$lines.Add("## Candidates")
foreach ($candidate in $candidates) {
    $lines.Add("- $($candidate.programName) ($($candidate.robotName), size=$($candidate.size))")
}
$lines | Set-Content -LiteralPath $summaryPath -Encoding UTF8

$backupCommands = New-Object System.Collections.Generic.List[string]
$backupCommands.Add("user $($config.UserName) $($config.Password)")
$backupCommands.Add("binary")
foreach ($candidate in $candidates) {
    $destination = Join-Path $backupRoot ([string]$candidate.robotName)
    $backupCommands.Add("get $($candidate.robotName) `"$destination`"")
}
$backupCommands.Add("quit")

Write-Host "Backing up $($candidates.Count) TP candidate files from robot $($config.RobotIp)"
$backupResult = Invoke-FtpScript -RobotIp $config.RobotIp -Commands $backupCommands.ToArray() -LogPath $backupLogPath
Assert-FtpSuccess -Result $backupResult -Operation "FTP backup"

foreach ($candidate in $candidates) {
    $backupPath = Join-Path $backupRoot ([string]$candidate.robotName)
    if (-not (Test-Path -LiteralPath $backupPath)) {
        throw "Backup missing for $($candidate.robotName): $backupPath"
    }

    $backupItem = Get-Item -LiteralPath $backupPath
    if ($backupItem.Length -le 0) {
        throw "Backup is empty for $($candidate.robotName): $backupPath"
    }

    if ($candidate.size -and [int64]$candidate.size -ne $backupItem.Length) {
        Write-Warning "Backup size differs from robot listing for $($candidate.robotName): listing=$($candidate.size), local=$($backupItem.Length)"
    }
}

if (-not $Execute) {
    Write-Host "Dry run complete. Re-run with -Execute to delete the backed-up candidates."
    [pscustomobject]@{
        RootProgram = $rootProgram
        OriginalCandidateCount = $originalCandidateCount
        PresentCandidateCount = $candidates.Count
        AlreadyMissingCount = $missingCandidates.Count
        Deleted = $false
        RunRoot = $runRoot
        PlanPath = $planPath
        SummaryPath = $summaryPath
        BackupRoot = $backupRoot
    }
    return
}

$deleteCommands = New-Object System.Collections.Generic.List[string]
$deleteCommands.Add("user $($config.UserName) $($config.Password)")
$deleteCommands.Add("binary")
foreach ($candidate in $candidates) {
    $deleteCommands.Add("delete $($candidate.robotName)")
}
$deleteCommands.Add("quit")

Write-Host "Deleting $($candidates.Count) TP non-dependency candidates from robot $($config.RobotIp)"
$deleteResult = Invoke-FtpScript -RobotIp $config.RobotIp -Commands $deleteCommands.ToArray() -LogPath $deleteLogPath
Assert-FtpSuccess -Result $deleteResult -Operation "FTP delete" -AllowFileErrors
$deleteResults = @(Get-DeleteResults -Output $deleteResult.Output -Candidates $candidates)
$deleteResults | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $deleteResultsPath -Encoding UTF8
$deletedCount = @($deleteResults | Where-Object { $_.status -eq "deleted" }).Count
$failedCount = @($deleteResults | Where-Object { $_.status -eq "failed" }).Count

[pscustomobject]@{
    RootProgram = $rootProgram
    OriginalCandidateCount = $originalCandidateCount
    PresentCandidateCount = $candidates.Count
    AlreadyMissingCount = $missingCandidates.Count
    DeletedCount = $deletedCount
    FailedDeleteCount = $failedCount
    Deleted = $true
    RunRoot = $runRoot
    PlanPath = $planPath
    SummaryPath = $summaryPath
    BackupRoot = $backupRoot
    BackupLogPath = $backupLogPath
    DeleteLogPath = $deleteLogPath
    DeleteResultsPath = $deleteResultsPath
}
