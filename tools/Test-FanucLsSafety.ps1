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

if (-not $expectedProgramName.StartsWith($config.ProgramPrefix.ToUpperInvariant())) {
    Add-Finding -Rule "ProgramPrefix" -Message "Program name must start with $($config.ProgramPrefix)."
}

$text = Get-Content -LiteralPath $lsItem.FullName -Raw
$programHeaders = [regex]::Matches($text, '(?im)^\s*/PROG\s+([A-Za-z][A-Za-z0-9_]*)\s*$')
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

foreach ($blocked in $blockedPatterns) {
    if ($text -match $blocked.Pattern) {
        Add-Finding -Rule $blocked.Rule -Message $blocked.Message -Pattern $blocked.Pattern
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
