[CmdletBinding()]
param(
    [string]$RootProgram = "F_MAIN",
    [string]$ConfigPath = "..\config\robot.psd1",
    [string]$OutputRoot = "generated\dependency-map",
    [switch]$IncludeAiPrograms,
    [switch]$ExcludeAiPrograms,
    [switch]$ExcludeGeneratedPrograms,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

if ($ExcludeAiPrograms) {
    $ExcludeGeneratedPrograms = $true
}
if ($IncludeAiPrograms -and $ExcludeGeneratedPrograms) {
    throw "Use only one generated-program policy switch. Generated programs are included by default; use -ExcludeGeneratedPrograms only for a deliberately non-generated view."
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

function Get-GeneratedProgramPrefixes {
    param([object]$Config)

    $prefixes = New-Object System.Collections.Generic.List[string]
    if ($Config.ProgramPrefix) {
        $prefixes.Add($Config.ProgramPrefix.ToUpperInvariant())
    }
    foreach ($prefix in @($Config.LegacyProgramPrefixes)) {
        if ($prefix) {
            $prefixes.Add($prefix.ToUpperInvariant())
        }
    }
    return @($prefixes.ToArray() | Sort-Object -Unique)
}

function Test-GeneratedProgramName {
    param(
        [string]$ProgramName,
        [string[]]$Prefixes
    )

    foreach ($prefix in @($Prefixes)) {
        if ($ProgramName.StartsWith($prefix)) {
            return $true
        }
    }
    return $false
}

function Test-LsMacroProgram {
    param([string]$LsPath)

    if (-not (Test-Path -LiteralPath $LsPath)) {
        return $false
    }

    $firstProgramLine = Get-Content -LiteralPath $LsPath | Where-Object { $_ -match '^\s*/PROG\s+' } | Select-Object -First 1
    return [bool]($firstProgramLine -match '(?i)^\s*/PROG\s+[A-Z][A-Z0-9_]{0,31}\s+Macro\b')
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

function Get-RobotProgramDirectory {
    param([object]$Config)

    $directory = Invoke-FtpScript -RobotIp $Config.RobotIp -Commands @(
        "user $($Config.UserName) $($Config.Password)",
        "binary",
        "dir *.TP",
        "dir *.PC",
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

        $extension = if ($name) { [System.IO.Path]::GetExtension($name).ToUpperInvariant() } else { $null }
        if (-not $name -or @(".TP", ".PC") -notcontains $extension) {
            continue
        }

        $programName = Get-ProgramName $name
        [pscustomobject]@{
            name = $name
            programName = $programName
            extension = $extension
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
$generatedProgramPrefixes = @(Get-GeneratedProgramPrefixes -Config $config)
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
$robotPrograms = @(Get-RobotProgramDirectory -Config $config)
$robotTpPrograms = @($robotPrograms | Where-Object { $_.extension -eq ".TP" })
$robotPcPrograms = @($robotPrograms | Where-Object { $_.extension -eq ".PC" })
$knownMacroPrograms = @(@($config.KnownMacroPrograms) | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { $_.ToUpperInvariant() } | Sort-Object -Unique)
$cleanupProtectedPrograms = @(@($config.CleanupProtectedPrograms) | ForEach-Object { [string]$_ } | Where-Object { $_ } | ForEach-Object { $_.ToUpperInvariant() } | Sort-Object -Unique)
$robotProgramMap = @{}
foreach ($entry in $robotPrograms) {
    if (-not $robotProgramMap.ContainsKey($entry.programName) -or $entry.extension -eq ".TP") {
        $robotProgramMap[$entry.programName] = $entry
    }
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
    $robotEntry = $robotProgramMap[$program]

    if ($robotEntry.extension -eq ".PC") {
        $programRecords[$program] = [pscustomobject]@{
            programName = $program
            status = "present-$($robotEntry.extension.TrimStart('.').ToLowerInvariant())"
            robotName = $robotEntry.name
            extension = $robotEntry.extension
            tpPath = $null
            lsPath = $null
            error = $null
            macroMarker = $false
            knownMacroProgram = $knownMacroPrograms -contains $program
            directCallCount = 0
            directRunCount = 0
            dynamicReferenceCount = 0
        }
        continue
    }

    $programDir = Join-Path $downloadsRoot $program
    if (-not (Test-Path -LiteralPath $programDir)) {
        New-Item -ItemType Directory -Path $programDir -Force | Out-Null
    }

    $downloadedTp = Join-Path (Join-Path $projectRoot "downloaded\tp") ($program + $robotEntry.extension)
    $decodedLs = Join-Path (Join-Path $projectRoot "downloaded\ls") ($program + ".LS")
    $copyTp = Join-Path $programDir ($program + $robotEntry.extension)
    $copyLs = Join-Path $programDir ($program + ".LS")
    $status = "decoded"
    $errorMessage = $null
    $macroMarker = $false

    try {
        & $reader -Program ($program + $robotEntry.extension) -ConfigPath $resolvedConfig -Force:$Force | Out-Null
        if (Test-Path -LiteralPath $downloadedTp) {
            Copy-Item -LiteralPath $downloadedTp -Destination $copyTp -Force
            Copy-Item -LiteralPath $downloadedTp -Destination (Join-Path $tpBackupRoot ($program + $robotEntry.extension)) -Force
        }
        if (Test-Path -LiteralPath $decodedLs) {
            Copy-Item -LiteralPath $decodedLs -Destination $copyLs -Force
        }
        $macroMarker = Test-LsMacroProgram -LsPath $copyLs
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
                calleeExtension = if ($robotProgramMap.ContainsKey($reference.target)) { $robotProgramMap[$reference.target].extension } else { $null }
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
        robotName = $robotEntry.name
        extension = $robotEntry.extension
        tpPath = if (Test-Path -LiteralPath $copyTp) { (Get-Item -LiteralPath $copyTp).FullName } else { $null }
        lsPath = if (Test-Path -LiteralPath $copyLs) { (Get-Item -LiteralPath $copyLs).FullName } else { $null }
        error = $errorMessage
        macroMarker = $macroMarker
        knownMacroProgram = $knownMacroPrograms -contains $program
        directCallCount = @($references | Where-Object { $_.instruction -eq "CALL" -and $_.type -eq "direct" }).Count
        directRunCount = @($references | Where-Object { $_.instruction -eq "RUN" -and $_.type -eq "direct" }).Count
        dynamicReferenceCount = @($references | Where-Object { $_.type -eq "dynamic" }).Count
    }
}

$requiredPrograms = @($visited.Keys | Sort-Object)
$macroMarkerPrograms = @($programRecords.Keys | Where-Object { $programRecords[$_].macroMarker } | Sort-Object)
$knownMacroProgramsOnRobot = @($knownMacroPrograms | Where-Object { $robotProgramMap.ContainsKey($_) })
$knownMacroProgramsMissing = @($knownMacroPrograms | Where-Object { -not $robotProgramMap.ContainsKey($_) })
$knownMacroProgramsNotReachable = @($knownMacroProgramsOnRobot | Where-Object { $requiredPrograms -notcontains $_ })
$unreachablePrograms = @($robotTpPrograms |
    Where-Object { $requiredPrograms -notcontains $_.programName } |
    Where-Object { $knownMacroPrograms -notcontains $_.programName } |
    Where-Object { $cleanupProtectedPrograms -notcontains $_.programName } |
    Sort-Object programName)
$generatedProgramsOnRobot = @($robotPrograms |
    Where-Object { Test-GeneratedProgramName -ProgramName $_.programName -Prefixes $generatedProgramPrefixes } |
    Sort-Object programName)
$generatedProgramsNotReachable = @($unreachablePrograms |
    Where-Object { Test-GeneratedProgramName -ProgramName $_.programName -Prefixes $generatedProgramPrefixes } |
    Sort-Object programName)
$backupDeleteCandidates = @($unreachablePrograms |
    Where-Object { -not $ExcludeGeneratedPrograms -or -not (Test-GeneratedProgramName -ProgramName $_.programName -Prefixes $generatedProgramPrefixes) } |
    Sort-Object programName)

$requiredRecords = @($requiredPrograms | ForEach-Object {
    if ($programRecords.ContainsKey($_)) {
        $programRecords[$_]
    } else {
        [pscustomobject]@{
            programName = $_
            status = "missing"
            robotName = $null
            extension = $null
            tpPath = $null
            lsPath = $null
            error = "Referenced program was not found on robot MD:"
            macroMarker = $false
            knownMacroProgram = $knownMacroPrograms -contains $_
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
    generatedProgramPrefixes = @($generatedProgramPrefixes)
    includeGeneratedPrograms = -not [bool]$ExcludeGeneratedPrograms
    excludeGeneratedPrograms = [bool]$ExcludeGeneratedPrograms
    includeAiPrograms = -not [bool]$ExcludeGeneratedPrograms
    excludeAiPrograms = [bool]$ExcludeGeneratedPrograms
    robotProgramCount = $robotPrograms.Count
    robotTpProgramCount = $robotTpPrograms.Count
    robotPcProgramCount = $robotPcPrograms.Count
    knownMacroProgramCount = $knownMacroPrograms.Count
    cleanupProtectedProgramCount = $cleanupProtectedPrograms.Count
    knownMacroProgramsOnRobotCount = $knownMacroProgramsOnRobot.Count
    knownMacroProgramsMissingCount = $knownMacroProgramsMissing.Count
    knownMacroProgramsNotReachableCount = $knownMacroProgramsNotReachable.Count
    macroMarkerProgramCount = $macroMarkerPrograms.Count
    generatedProgramCount = $generatedProgramsOnRobot.Count
    requiredProgramCount = $requiredRecords.Count
    generatedProgramsNotReachableCount = $generatedProgramsNotReachable.Count
    backupDeleteCandidateCount = $backupDeleteCandidates.Count
    analysisRoot = (Get-Item -LiteralPath $analysisRoot).FullName
    tpBackupRoot = (Get-Item -LiteralPath $tpBackupRoot).FullName
    requiredPrograms = @($requiredRecords)
    dependencyEdges = @($dependencyEdges.ToArray())
    missingDependencies = @($missing.Keys | Sort-Object)
    dynamicReferences = @($dynamicReferences.ToArray())
    decodeFailures = @($decodeFailures.ToArray())
    knownMacroPrograms = @($knownMacroPrograms | ForEach-Object {
        [ordered]@{
            programName = $_
            presentOnRobot = $robotProgramMap.ContainsKey($_)
            reachableFromRoot = $requiredPrograms -contains $_
            decodedMacroMarker = if ($programRecords.ContainsKey($_)) { [bool]$programRecords[$_].macroMarker } else { $false }
            extension = if ($robotProgramMap.ContainsKey($_)) { $robotProgramMap[$_].extension } else { $null }
            robotName = if ($robotProgramMap.ContainsKey($_)) { $robotProgramMap[$_].name } else { $null }
            cleanupCandidate = $false
            reason = "Configured macro-assigned TP program. Macro assignments are controller configuration, not .MR files."
        }
    })
    macroMarkerPrograms = @($macroMarkerPrograms)
    cleanupProtectedPrograms = @($cleanupProtectedPrograms | ForEach-Object {
        [ordered]@{
            programName = $_
            presentOnRobot = $robotProgramMap.ContainsKey($_)
            reachableFromRoot = $requiredPrograms -contains $_
            extension = if ($robotProgramMap.ContainsKey($_)) { $robotProgramMap[$_].extension } else { $null }
            robotName = if ($robotProgramMap.ContainsKey($_)) { $robotProgramMap[$_].name } else { $null }
            cleanupCandidate = $false
            reason = "Configured cleanup-protected program. Never include in backup/delete candidates."
        }
    })
    generatedProgramsNotReachable = @($generatedProgramsNotReachable | ForEach-Object {
        [ordered]@{
            programName = $_.programName
            robotName = $_.name
            size = $_.size
            includedInBackupDeleteCandidates = -not [bool]$ExcludeGeneratedPrograms
            reason = "Generated-prefix program is present on robot MD: but not reachable from $root by direct CALL/RUN analysis."
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
$lines.Add("- Robot TP programs seen: $($robotTpPrograms.Count)")
$lines.Add("- Robot KAREL .PC programs seen: $($robotPcPrograms.Count)")
$lines.Add("- Known macro TP programs configured: $($knownMacroPrograms.Count)")
$lines.Add("- Known macro TP programs present on robot: $($knownMacroProgramsOnRobot.Count)")
$lines.Add("- Cleanup-protected programs configured: $($cleanupProtectedPrograms.Count)")
$lines.Add("- Decoded ``/PROG ... Macro`` markers found in required closure: $($macroMarkerPrograms.Count)")
$lines.Add("- Generated program prefixes: $($generatedProgramPrefixes -join ', ')")
$lines.Add("- Generated-prefix programs seen: $($generatedProgramsOnRobot.Count)")
$lines.Add("- Required programs from direct CALL/RUN closure: $($requiredRecords.Count)")
$lines.Add("- Generated-prefix programs not reachable from direct CALL/RUN closure: $($generatedProgramsNotReachable.Count)")
$lines.Add("- Backup/delete candidates: $($backupDeleteCandidates.Count)")
$lines.Add("- Include generated-prefix programs in backup/delete candidates: $(-not [bool]$ExcludeGeneratedPrograms)")
$lines.Add("- Analysis folder: $analysisRoot")
$lines.Add("- TP backup folder for decoded dependency set: $tpBackupRoot")
$lines.Add("")
$lines.Add("## Required Programs")
foreach ($program in $requiredRecords) {
    $role = if ($program.macroMarker) { ", macroMarker=true" } elseif ($program.knownMacroProgram) { ", knownMacroProgram=true" } else { "" }
    $lines.Add("- $($program.programName): $($program.status)$role, directCalls=$($program.directCallCount), directRuns=$($program.directRunCount), dynamicReferences=$($program.dynamicReferenceCount)")
}
$lines.Add("")
$lines.Add("## Macro Programs")
if ($knownMacroPrograms.Count -eq 0 -and $macroMarkerPrograms.Count -eq 0) {
    $lines.Add("- none configured or detected")
} else {
    $lines.Add("- Macro programs are TP programs whose decoded LS ``/PROG`` line includes ``Macro``; ``.MR`` is not treated as a proven robot file extension.")
    foreach ($program in @($knownMacroPrograms | Sort-Object)) {
        $present = if ($knownMacroProgramsOnRobot -contains $program) { "present" } else { "missing" }
        $reachable = if ($requiredPrograms -contains $program) { "reachable" } else { "not reachable" }
        $marker = if ($macroMarkerPrograms -contains $program) { "decoded marker found" } else { "decoded marker not observed in this closure" }
        $lines.Add("- $($program): configured, $present, $reachable, $marker")
    }
    foreach ($program in @($macroMarkerPrograms | Where-Object { $knownMacroPrograms -notcontains $_ } | Sort-Object)) {
        $lines.Add("- $($program): decoded ``/PROG ... Macro`` marker found")
    }
}
$lines.Add("")
$lines.Add("## Cleanup-Protected Programs")
if ($cleanupProtectedPrograms.Count -eq 0) {
    $lines.Add("- none configured")
} else {
    foreach ($program in @($cleanupProtectedPrograms | Sort-Object)) {
        $present = if ($robotProgramMap.ContainsKey($program)) { "present" } else { "missing" }
        $reachable = if ($requiredPrograms -contains $program) { "reachable" } else { "not reachable" }
        $lines.Add("- $($program): configured, $present, $reachable, excluded from backup/delete candidates")
    }
}
$lines.Add("")
$lines.Add("## Dependency Edges")
if ($dependencyEdges.Count -eq 0) {
    $lines.Add("- none")
} else {
    foreach ($edge in @($dependencyEdges.ToArray() | Sort-Object caller, callee, lineNumber)) {
        $present = if ($edge.calleePresentOnRobot) { "present$($edge.calleeExtension)" } else { "missing" }
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
$lines.Add("## Generated Programs Not Reachable")
if ($generatedProgramsNotReachable.Count -eq 0) {
    $lines.Add("- none")
} else {
    if ($ExcludeGeneratedPrograms) {
        $lines.Add("- These are listed separately and excluded from Backup/Delete Candidates because -ExcludeGeneratedPrograms was used.")
    }
    foreach ($program in @($generatedProgramsNotReachable | Sort-Object programName)) {
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
    GeneratedProgramNotReachableCount = $generatedProgramsNotReachable.Count
    BackupDeleteCandidateCount = $backupDeleteCandidates.Count
    MissingDependencyCount = $missing.Count
    DynamicReferenceCount = $dynamicReferences.Count
    AnalysisRoot = (Get-Item -LiteralPath $analysisRoot).FullName
    JsonPath = (Get-Item -LiteralPath $jsonPath).FullName
    MarkdownPath = (Get-Item -LiteralPath $markdownPath).FullName
}
