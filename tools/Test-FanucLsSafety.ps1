param(
    [Parameter(Mandatory = $true)]
    [string]$LsPath,

    [string]$ProgramName,
    [string]$ConfigPath = "..\config\robot.psd1",
    [string]$SafetyRulesPath = "..\config\safety-rules.psd1",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

if ([System.IO.Path]::IsPathRooted($SafetyRulesPath)) {
    $resolvedSafetyRules = Resolve-Path -LiteralPath $SafetyRulesPath
} else {
    $resolvedSafetyRules = Resolve-Path -LiteralPath (Join-Path $scriptRoot $SafetyRulesPath)
}

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig
$configRoot = Split-Path -Parent $resolvedConfig
$safetyRules = Import-PowerShellDataFile -LiteralPath $resolvedSafetyRules
$resolvedLs = Resolve-Path -LiteralPath $LsPath
$lsItem = Get-Item -LiteralPath $resolvedLs
$expectedProgramName = if ($ProgramName) {
    $ProgramName.ToUpperInvariant()
} else {
    $lsItem.BaseName.ToUpperInvariant()
}

$result = [ordered]@{
    Path = $lsItem.FullName
    ProgramName = $expectedProgramName
    SourceProgramName = $null
    IsSafe = $true
    Findings = @()
}

function Add-Finding {
    param(
        [string]$Rule,
        [string]$Message,
        [string]$Pattern = $null
    )

    $result.IsSafe = $false
    $finding = [ordered]@{
        Rule = $Rule
        Message = $Message
    }

    if ($Pattern) {
        $finding.Pattern = $Pattern
    }

    $result.Findings += [pscustomobject]$finding
}

function Get-AllowedProgramPrefixes {
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

function Resolve-CellMapPath {
    param([object]$Config)

    if ($Config.CellMapPath) {
        if ([System.IO.Path]::IsPathRooted($Config.CellMapPath)) {
            return $Config.CellMapPath
        }

        $projectCandidate = Join-Path $projectRoot $Config.CellMapPath
        if (Test-Path -LiteralPath $projectCandidate) {
            return $projectCandidate
        }

        return Join-Path $configRoot $Config.CellMapPath
    }

    return Join-Path $projectRoot "config\cell-map.psd1"
}

function Get-AllowedRunPrograms {
    param([object]$Config)

    $cellMapPath = Resolve-CellMapPath -Config $Config
    if (-not (Test-Path -LiteralPath $cellMapPath)) {
        return @()
    }

    $cellMap = Import-PowerShellDataFile -LiteralPath $cellMapPath
    return @($cellMap.Runs.Allowed | ForEach-Object {
        if ($_.Program) {
            $_.Program.ToUpperInvariant()
        }
    } | Sort-Object -Unique)
}

function Get-LsDefaultGroup {
    param([string]$Text)

    $matches = [regex]::Matches($Text, '(?im)^\s*DEFAULT_GROUP\s*=\s*([^;]+)\s*;')
    if ($matches.Count -ne 1) {
        return $null
    }

    return ($matches[0].Groups[1].Value -replace '\s+', '').ToUpperInvariant()
}

function Test-LsBodyOwnsMotionResource {
    param(
        [string]$Text,
        [string]$BaseDirectory,
        [System.Collections.Generic.HashSet[string]]$VisitedPrograms
    )

    if ($Text -match '(?im)^\s*\d+:\s*[JLC]\s+') {
        return $true
    }

    if ($Text -match '(?im)^\s*\d+:\s*PR\[(?:GP\d+:)?[^\]]+\]\s*=') {
        return $true
    }

    $callMatches = [regex]::Matches($Text, '(?im)^\s*\d+:\s*CALL\s+([A-Za-z][A-Za-z0-9_]*)\b')
    foreach ($callMatch in $callMatches) {
        $target = $callMatch.Groups[1].Value.ToUpperInvariant()
        if ($VisitedPrograms.Contains($target)) {
            continue
        }
        [void]$VisitedPrograms.Add($target)

        $candidatePaths = @(
            (Join-Path $BaseDirectory ($target + ".LS")),
            (Join-Path (Join-Path $projectRoot "generated\sources") ($target + ".LS"))
        ) | Select-Object -Unique

        foreach ($candidatePath in $candidatePaths) {
            if (-not (Test-Path -LiteralPath $candidatePath)) {
                continue
            }

            $targetText = Get-Content -LiteralPath $candidatePath -Raw
            $targetGroup = Get-LsDefaultGroup -Text $targetText
            if ($targetGroup -and $targetGroup -ne "*,*,*,*,*,*,*,*") {
                return $true
            }

            if (Test-LsBodyOwnsMotionResource -Text $targetText -BaseDirectory (Split-Path -Parent $candidatePath) -VisitedPrograms $VisitedPrograms) {
                return $true
            }
        }
    }

    return $false
}

$allowedProgramPrefixes = @(Get-AllowedProgramPrefixes -Config $config)
$allowedRunPrograms = @(Get-AllowedRunPrograms -Config $config)

if (-not @($allowedProgramPrefixes | Where-Object { $expectedProgramName.StartsWith($_) }).Count) {
    Add-Finding -Rule "ProgramPrefix" -Message "Program name must start with one of: $($allowedProgramPrefixes -join ', ')."
}

$text = Get-Content -LiteralPath $lsItem.FullName -Raw
$programHeaders = [regex]::Matches($text, '(?im)^\s*/PROG\s+([A-Za-z][A-Za-z0-9_]*)(?:\s+Macro)?\s*$')
if ($programHeaders.Count -ne 1) {
    Add-Finding -Rule "ProgramHeader" -Message "Source must contain exactly one valid /PROG header."
} else {
    $sourceProgramName = $programHeaders[0].Groups[1].Value.ToUpperInvariant()
    $result.SourceProgramName = $sourceProgramName
    if ($sourceProgramName -ne $expectedProgramName) {
        Add-Finding -Rule "ProgramHeaderMatch" -Message "Source /PROG name ($sourceProgramName) must match file name ($expectedProgramName)."
    }
}

$blockedPatterns = @($safetyRules.BlockedPatterns)
$allowedSystemVariables = @($safetyRules.AllowedSystemVariables | ForEach-Object { $_.ToUpperInvariant() })

foreach ($blocked in $blockedPatterns) {
    if ($blocked.Rule -eq "SystemVariable") {
        $matches = [regex]::Matches($text, $blocked.Pattern)
        foreach ($match in $matches) {
            $systemVariable = $match.Value.ToUpperInvariant()
            if ($allowedSystemVariables -notcontains $systemVariable) {
                Add-Finding -Rule $blocked.Rule -Message $blocked.Message -Pattern $blocked.Pattern
            }
        }
        continue
    }

    if ($blocked.Rule -eq "Run" -and $text -match $blocked.Pattern) {
        $runMatches = [regex]::Matches($text, '(?im)^\s*\d+:\s+RUN\s+([A-Za-z][A-Za-z0-9_]*)\s*;')
        if ($runMatches.Count -eq 0) {
            continue
        }

        foreach ($runMatch in $runMatches) {
            $target = $runMatch.Groups[1].Value.ToUpperInvariant()
            if ($allowedRunPrograms -notcontains $target) {
                Add-Finding -Rule "RunProgramNotAllowed" -Message "RUN target $target is not allowed by config\cell-map.psd1." -Pattern $blocked.Pattern
            }
        }
        continue
    }

    if ($text -match $blocked.Pattern) {
        Add-Finding -Rule $blocked.Rule -Message $blocked.Message -Pattern $blocked.Pattern
    }
}

if ($text -match '!\s*\(') {
    Add-Finding -Rule "GroupedNegation" -Message "Use ! only directly in front of a single signal/entity, not in front of a grouped expression. Prefer affirmative signal/state names to avoid double negatives." -Pattern '!\s*\('
}

$defaultGroupMatches = [regex]::Matches($text, '(?im)^\s*DEFAULT_GROUP\s*=\s*([^;]+)\s*;')
if ($defaultGroupMatches.Count -ne 1) {
    Add-Finding -Rule "DefaultGroupRequired" -Message "LS source must declare exactly one DEFAULT_GROUP attribute."
} else {
    $defaultGroup = ($defaultGroupMatches[0].Groups[1].Value -replace '\s+', '').ToUpperInvariant()
    $hasMotionInstruction = $text -match '(?im)^\s*\d+:\s*[JLC]\s+'
    $hasPrCalculation = $text -match '(?im)^\s*\d+:\s*PR\[(?:GP\d+:)?[^\]]+\]\s*='
    $callsMotionResource = Test-LsBodyOwnsMotionResource -Text $text -BaseDirectory (Split-Path -Parent $lsItem.FullName) -VisitedPrograms ([System.Collections.Generic.HashSet[string]]::new())
    $isMotionAffecting = $hasMotionInstruction -or $hasPrCalculation -or $callsMotionResource
    if (-not $isMotionAffecting -and $defaultGroup -ne "*,*,*,*,*,*,*,*") {
        Add-Finding -Rule "NoMotionDefaultGroup" -Message "No-motion generated programs must use DEFAULT_GROUP = *,*,*,*,*,*,*,* so they do not claim a motion group."
    }
    if ($hasPrCalculation -and $defaultGroup -eq "*,*,*,*,*,*,*,*") {
        Add-Finding -Rule "PrCalculationDefaultGroup" -Message "PR calculations are motion-affecting resource writes. Use a reviewed motion group mask instead of wildcard DEFAULT_GROUP unless a project explicitly approves FANUC No motion PR operate mode."
    }
}

$output = [pscustomobject]$result
if (-not $Quiet) {
    $output
}

if (-not $result.IsSafe) {
    $messages = $result.Findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "LS safety validation failed for $($lsItem.FullName):`n$($messages -join "`n")"
}
