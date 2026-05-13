[CmdletBinding()]
param(
    [string]$RootProgram = "F_MAIN",
    [string]$ConfigPath = "..\config\robot.psd1",
    [string]$OutputRoot = "generated\dependency-map",
    [switch]$IncludeAiPrograms,
    [switch]$ExcludeAiPrograms,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ($IncludeAiPrograms -and $ExcludeAiPrograms) {
    throw "Use only one AI program policy switch. AI_* programs are included by default; use -ExcludeAiPrograms only for a deliberately non-AI view."
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $projectRoot $Path
}

function Get-ProgramName {
    param([string]$Name)

    return ([System.IO.Path]::GetFileNameWithoutExtension($Name)).ToUpperInvariant()
}

function Get-ProgramReferences {
    param([string]$LsPath)

    if (-not (Test-Path -LiteralPath $LsPath)) {
        return @()
    }

    $references = New-Object System.Collections.Generic.List[object]
    $lines = Get-Content -LiteralPath $LsPath
    $inMn = $false
    foreach ($line in $lines) {
        if ($line -match '^\s*/MN') {
            $inMn = $true
            continue
        }
        if ($line -match '^\s*/POS') {
            $inMn = $false
        }
        if (-not $inMn) {
            continue
        }

        $normalizedLine = [regex]::Replace($line, '\s+', ' ').Trim()
        $lineNumber = $null
        $statementText = $normalizedLine
        if ($normalizedLine -match '^(\d+)\s*:') {
            $lineNumber = [int]$Matches[1]
            $statementText = $normalizedLine.Substring($Matches[0].Length).Trim()
        }
        if ($statementText -match '^(?:!|--|//)') {
            continue
        }

        $directCalls = [regex]::Matches($statementText, '(?i)\bCALL\s+([A-Z][A-Z0-9_]{0,31})\b')
        foreach ($call in $directCalls) {
            $target = $call.Groups[1].Value.ToUpperInvariant()
            $references.Add([pscustomobject]@{
                instruction = "CALL"
                type = "direct"
                target = $target
                lineNumber = $lineNumber
                line = $normalizedLine
            })
        }

        if ($statementText -match '(?i)\bCALL\s+([A-Z]*\[[^\]]+\])') {
            $references.Add([pscustomobject]@{
                instruction = "CALL"
                type = "dynamic"
                target = $Matches[1].ToUpperInvariant()
                lineNumber = $lineNumber
                line = $normalizedLine
            })
        }
        $directRuns = [regex]::Matches($statementText, '(?i)\bRUN\s+([A-Z][A-Z0-9_]{0,31})\b')
        foreach ($run in $directRuns) {
            $target = $run.Groups[1].Value.ToUpperInvariant()
            $references.Add([pscustomobject]@{
                instruction = "RUN"
                type = "direct"
                target = $target
                lineNumber = $lineNumber
                line = $normalizedLine
            })
        }

        if ($statementText -match '(?i)\bRUN\s+([A-Z]*\[[^\]]+\])') {
            $references.Add([pscustomobject]@{
                instruction = "RUN"
                type = "dynamic"
                target = $Matches[1].ToUpperInvariant()
                lineNumber = $lineNumber
                line = $normalizedLine
            })
        }
    }

    return $references.ToArray()
}

function Invoke-FtpScript {
    param(
        [string[]]$Commands,
        [string]$RobotIp
    )

    $ftpScript = Join-Path $env:TEMP ("fanuc-deps-{0}.ftp" -f ([Guid]::NewGuid().ToString("N")))
    try {
        Set-Content -LiteralPath $ftpScript -Value $Commands -Encoding ASCII
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = & ftp.exe -n -s:$ftpScript $RobotIp 2>&1
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
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

function Get-RobotTpDirectory {
    param([object]$Config)

    $directory = Invoke-FtpScript -RobotIp $Config.RobotIp -Commands @(
        "user $($Config.UserName) $($Config.Password)",
        "binary",
        "dir *.TP",
        "quit"
    )

    $ftpText = $directory.Output -join "`n"
    if (
        $directory.ExitCode -ne 0 -or
        $ftpText -match '(?i)connect\s*:' -or
        $ftpText -match '(?i)not connected' -or
        $ftpText -match '(?i)login failed' -or
        $ftpText -match '(?i)unknown host' -or
        ($ftpText -match '(?im)^5\d\d\s' -and $ftpText -notmatch '(?im)^226\s')
    ) {
        throw "FTP directory listing failed:`n$ftpText"
    }

    $records = foreach ($line in $directory.Output) {
        $text = [string]$line
        if ([string]::IsNullOrWhiteSpace($text)) {
            continue
        }

        $name = $null
        $size = $null
        if ($text -match '^\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\d+\s+\d{4}\s+(.+)$') {
            $size = [int64]$matches[1]
            $name = $matches[2].Trim()
        } elseif ($text -match '^\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\d+\s+\d{1,2}:\d{2}\s+(.+)$') {
            $size = [int64]$matches[1]
            $name = $matches[2].Trim()
        }

        if (-not $name -or [System.IO.Path]::GetExtension($name).ToUpperInvariant() -ne ".TP") {
            continue
        }

        $programName = Get-ProgramName $name
        [pscustomobject]@{
            name = $name
            programName = $programName
            extension = ".TP"
            size = $size
            rawLine = $text
        }
    }

    return @($records | Sort-Object programName, name)
}

$resolvedConfig = if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    (Resolve-Path -LiteralPath $ConfigPath).Path
} else {
    (Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)).Path
}
$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig
$root = Get-ProgramName $RootProgram
$resolvedOutputRoot = Resolve-ProjectPath $OutputRoot
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$analysisRoot = Join-Path $resolvedOutputRoot ("$stamp-$root")
$downloadsRoot = Join-Path $analysisRoot "programs"
$tpBackupRoot = Join-Path $analysisRoot "backup-tp"
foreach ($path in @($analysisRoot, $downloadsRoot, $tpBackupRoot)) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

$reader = Join-Path $scriptRoot "Read-FanucTpProgram.ps1"
$robotPrograms = @(Get-RobotTpDirectory -Config $config)
$robotProgramMap = @{}
foreach ($entry in $robotPrograms) {
    $robotProgramMap[$entry.programName] = $entry
}

$queue = New-Object System.Collections.Generic.Queue[string]
$visited = @{}
$missing = @{}
$decodeFailures = New-Object System.Collections.Generic.List[object]
$dependencyEdges = New-Object System.Collections.Generic.List[object]
$dynamicReferences = New-Object System.Collections.Generic.List[object]
$programRecords = @{}
$queue.Enqueue($root)

while ($queue.Count -gt 0) {
    $program = $queue.Dequeue().ToUpperInvariant()
    if ($visited.ContainsKey($program)) {
        continue
    }
    $visited[$program] = $true

    if (-not $robotProgramMap.ContainsKey($program)) {
        $missing[$program] = $true
        continue
    }

    $programDir = Join-Path $downloadsRoot $program
    if (-not (Test-Path -LiteralPath $programDir)) {
        New-Item -ItemType Directory -Path $programDir -Force | Out-Null
    }

    $downloadedTp = Join-Path (Join-Path $projectRoot "downloaded\tp") ($program + ".TP")
    $decodedLs = Join-Path (Join-Path $projectRoot "downloaded\ls") ($program + ".LS")
    $copyTp = Join-Path $programDir ($program + ".TP")
    $copyLs = Join-Path $programDir ($program + ".LS")
    $status = "decoded"
    $errorMessage = $null

    try {
        & $reader -Program $program -ConfigPath $resolvedConfig -Force:$Force | Out-Null
        if (Test-Path -LiteralPath $downloadedTp) {
            Copy-Item -LiteralPath $downloadedTp -Destination $copyTp -Force
            Copy-Item -LiteralPath $downloadedTp -Destination (Join-Path $tpBackupRoot ($program + ".TP")) -Force
        }
        if (Test-Path -LiteralPath $decodedLs) {
            Copy-Item -LiteralPath $decodedLs -Destination $copyLs -Force
        }
    } catch {
        $status = "failed"
        $errorMessage = $_.Exception.Message
        $decodeFailures.Add([pscustomobject]@{
            programName = $program
            error = $errorMessage
        })
    }

    $references = if ($status -eq "decoded") { @(Get-ProgramReferences -LsPath $copyLs) } else { @() }
    foreach ($reference in $references) {
        if ($reference.type -eq "direct") {
            $dependencyEdges.Add([pscustomobject]@{
                caller = $program
                callee = $reference.target
                instruction = $reference.instruction
                lineNumber = $reference.lineNumber
                line = $reference.line
                calleePresentOnRobot = $robotProgramMap.ContainsKey($reference.target)
            })
            if (-not $visited.ContainsKey($reference.target)) {
                $queue.Enqueue($reference.target)
            }
        } else {
            $dynamicReferences.Add([pscustomobject]@{
                caller = $program
                instruction = $reference.instruction
                target = $reference.target
                lineNumber = $reference.lineNumber
                line = $reference.line
            })
        }
    }

    $programRecords[$program] = [pscustomobject]@{
        programName = $program
        status = $status
        tpPath = if (Test-Path -LiteralPath $copyTp) { (Get-Item -LiteralPath $copyTp).FullName } else { $null }
        lsPath = if (Test-Path -LiteralPath $copyLs) { (Get-Item -LiteralPath $copyLs).FullName } else { $null }
        error = $errorMessage
        directCallCount = @($references | Where-Object { $_.instruction -eq "CALL" -and $_.type -eq "direct" }).Count
        directRunCount = @($references | Where-Object { $_.instruction -eq "RUN" -and $_.type -eq "direct" }).Count
        dynamicReferenceCount = @($references | Where-Object { $_.type -eq "dynamic" }).Count
    }
}

$requiredPrograms = @($visited.Keys | Sort-Object)
$unreachablePrograms = @($robotPrograms |
    Where-Object { $requiredPrograms -notcontains $_.programName } |
    Sort-Object programName)
$aiProgramsOnRobot = @($robotPrograms |
    Where-Object { $_.programName -like "AI_*" } |
    Sort-Object programName)
$aiProgramsNotReachable = @($unreachablePrograms |
    Where-Object { $_.programName -like "AI_*" } |
    Sort-Object programName)
$backupDeleteCandidates = @($unreachablePrograms |
    Where-Object { -not $ExcludeAiPrograms -or $_.programName -notlike "AI_*" } |
    Sort-Object programName)

$requiredRecords = @($requiredPrograms | ForEach-Object {
    if ($programRecords.ContainsKey($_)) {
        $programRecords[$_]
    } else {
        [pscustomobject]@{
            programName = $_
            status = "missing"
            tpPath = $null
            lsPath = $null
            error = "Referenced program was not found on robot MD:"
            directCallCount = 0
            directRunCount = 0
            dynamicReferenceCount = 0
        }
    }
})

$report = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    rootProgram = $root
    robotIp = $config.RobotIp
    includeAiPrograms = -not [bool]$ExcludeAiPrograms
    excludeAiPrograms = [bool]$ExcludeAiPrograms
    robotProgramCount = $robotPrograms.Count
    aiProgramCount = $aiProgramsOnRobot.Count
    requiredProgramCount = $requiredRecords.Count
    aiProgramsNotReachableCount = $aiProgramsNotReachable.Count
    backupDeleteCandidateCount = $backupDeleteCandidates.Count
    analysisRoot = (Get-Item -LiteralPath $analysisRoot).FullName
    tpBackupRoot = (Get-Item -LiteralPath $tpBackupRoot).FullName
    requiredPrograms = @($requiredRecords)
    dependencyEdges = @($dependencyEdges.ToArray())
    missingDependencies = @($missing.Keys | Sort-Object)
    dynamicReferences = @($dynamicReferences.ToArray())
    decodeFailures = @($decodeFailures.ToArray())
    aiProgramsNotReachable = @($aiProgramsNotReachable | ForEach-Object {
        [ordered]@{
            programName = $_.programName
            robotName = $_.name
            size = $_.size
            includedInBackupDeleteCandidates = -not [bool]$ExcludeAiPrograms
            reason = "AI_* program is present on robot MD: but not reachable from $root by direct CALL/RUN analysis."
        }
    })
    backupDeleteCandidates = @($backupDeleteCandidates | ForEach-Object {
        [ordered]@{
            programName = $_.programName
            robotName = $_.name
            size = $_.size
            reason = "Present on robot MD: but not reachable from $root by direct CALL/RUN analysis."
            recommendedAction = "Back up before any deletion; confirm this program is not selected by schedules, macros, BG logic, PNS/RSR, UOP, KAREL, HMI, or operator procedures."
        }
    })
    safetyNotes = @(
        "This is a static direct CALL/RUN dependency map from decoded LS.",
        "Dynamic CALL/RUN references, macros, BG logic, PNS/RSR selection, HMI/PLC starts, KAREL, and operator procedures can require programs not reachable from $root.",
        "Do not delete from the robot until the backup is verified and the candidate list is reviewed at the controller/project level."
    )
}

$jsonPath = Join-Path $analysisRoot "dependency-map.json"
$markdownPath = Join-Path $analysisRoot "dependency-map.md"
$report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $jsonPath -Encoding ASCII

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# FANUC TP Dependency Map: $root")
$lines.Add("")
$lines.Add("- Robot IP: $($config.RobotIp)")
$lines.Add("- Robot TP programs seen: $($robotPrograms.Count)")
$lines.Add("- AI_* TP programs seen: $($aiProgramsOnRobot.Count)")
$lines.Add("- Required programs from direct CALL/RUN closure: $($requiredRecords.Count)")
$lines.Add("- AI_* programs not reachable from direct CALL/RUN closure: $($aiProgramsNotReachable.Count)")
$lines.Add("- Backup/delete candidates: $($backupDeleteCandidates.Count)")
$lines.Add("- Include AI_* programs in backup/delete candidates: $(-not [bool]$ExcludeAiPrograms)")
$lines.Add("- Analysis folder: $analysisRoot")
$lines.Add("- TP backup folder for decoded dependency set: $tpBackupRoot")
$lines.Add("")
$lines.Add("## Required Programs")
foreach ($program in $requiredRecords) {
    $lines.Add("- $($program.programName): $($program.status), directCalls=$($program.directCallCount), directRuns=$($program.directRunCount), dynamicReferences=$($program.dynamicReferenceCount)")
}
$lines.Add("")
$lines.Add("## Dependency Edges")
if ($dependencyEdges.Count -eq 0) {
    $lines.Add("- none")
} else {
    foreach ($edge in @($dependencyEdges.ToArray() | Sort-Object caller, callee, lineNumber)) {
        $present = if ($edge.calleePresentOnRobot) { "present" } else { "missing" }
        $lines.Add("- $($edge.caller) -[$($edge.instruction)]-> $($edge.callee) at line $($edge.lineNumber) ($present): $($edge.line)")
    }
}
$lines.Add("")
$lines.Add("## Missing Dependencies")
if ($missing.Count -eq 0) {
    $lines.Add("- none")
} else {
    foreach ($program in @($missing.Keys | Sort-Object)) {
        $lines.Add("- $program")
    }
}
$lines.Add("")
$lines.Add("## Dynamic References")
if ($dynamicReferences.Count -eq 0) {
    $lines.Add("- none found")
} else {
    foreach ($reference in @($dynamicReferences.ToArray() | Sort-Object caller, lineNumber)) {
        $lines.Add("- $($reference.caller) $($reference.instruction) line $($reference.lineNumber): $($reference.line)")
    }
}
$lines.Add("")
$lines.Add("## AI Programs Not Reachable")
if ($aiProgramsNotReachable.Count -eq 0) {
    $lines.Add("- none")
} else {
    if ($ExcludeAiPrograms) {
        $lines.Add("- These are listed separately and excluded from Backup/Delete Candidates because -ExcludeAiPrograms was used.")
    }
    foreach ($program in @($aiProgramsNotReachable | Sort-Object programName)) {
        $lines.Add("- $($program.programName) ($($program.name), size=$($program.size)): not reachable from $root by direct CALL/RUN analysis")
    }
}
$lines.Add("")
$lines.Add("## Backup/Delete Candidates")
if ($backupDeleteCandidates.Count -eq 0) {
    $lines.Add("- none")
} else {
    foreach ($candidate in @($backupDeleteCandidates | Sort-Object programName)) {
        $lines.Add("- $($candidate.programName) ($($candidate.name), size=$($candidate.size)): not reachable from $root by direct CALL/RUN analysis")
    }
}
$lines.Add("")
$lines.Add("## Safety Notes")
foreach ($note in @($report.safetyNotes)) {
    $lines.Add("- $note")
}
$lines | Set-Content -LiteralPath $markdownPath -Encoding ASCII

[pscustomobject]@{
    RootProgram = $root
    RequiredProgramCount = $requiredRecords.Count
    AiProgramNotReachableCount = $aiProgramsNotReachable.Count
    BackupDeleteCandidateCount = $backupDeleteCandidates.Count
    MissingDependencyCount = $missing.Count
    DynamicReferenceCount = $dynamicReferences.Count
    AnalysisRoot = (Get-Item -LiteralPath $analysisRoot).FullName
    JsonPath = (Get-Item -LiteralPath $jsonPath).FullName
    MarkdownPath = (Get-Item -LiteralPath $markdownPath).FullName
}
