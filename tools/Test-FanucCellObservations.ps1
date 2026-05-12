param(
    [string]$ObservationPath = "..\config\cell-observations.psd1",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([System.IO.Path]::IsPathRooted($ObservationPath)) {
    $resolvedObservation = Resolve-Path -LiteralPath $ObservationPath
} else {
    $resolvedObservation = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ObservationPath)
}

$resolvedObservationPath = $resolvedObservation.Path
$observations = Import-PowerShellDataFile -LiteralPath $resolvedObservationPath
$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param(
        [string]$Rule,
        [string]$Message
    )

    $findings.Add([pscustomobject]@{
        Rule = $Rule
        Message = $Message
    })
}

$registers = @{}
foreach ($entry in @($observations.Registers)) {
    if ($null -eq $entry) { continue }
    if ($null -eq $entry.Register -or [int]$entry.Register -lt 1) {
        Add-Finding -Rule "RegisterInvalid" -Message "Register observations must include Register >= 1."
        continue
    }
    $key = [int]$entry.Register
    if ($registers.ContainsKey($key)) {
        Add-Finding -Rule "RegisterDuplicate" -Message "R[$key] appears more than once."
    }
    $registers[$key] = $true
}

$signals = @{}
foreach ($entry in @($observations.IoSignals)) {
    if ($null -eq $entry) { continue }
    if (-not $entry.Signal -or $entry.Signal -notmatch '^(DI|DO|RI|RO)\[[1-9][0-9]*\]$') {
        Add-Finding -Rule "SignalInvalid" -Message "IO observations must include Signal like DI[1], DO[1], RI[1], or RO[1]."
        continue
    }
    $key = $entry.Signal.ToUpperInvariant()
    if ($signals.ContainsKey($key)) {
        Add-Finding -Rule "SignalDuplicate" -Message "$key appears more than once."
    }
    $signals[$key] = $true
}

$programs = @{}
foreach ($entry in @($observations.ProgramPresence)) {
    if ($null -eq $entry) { continue }
    if (-not $entry.Program -or $entry.Program -cnotmatch '^[A-Z][A-Z0-9_]{0,31}$') {
        Add-Finding -Rule "ProgramInvalid" -Message "Program observations must include an uppercase FANUC-compatible Program name."
        continue
    }
    $key = $entry.Program.ToUpperInvariant()
    if ($programs.ContainsKey($key)) {
        Add-Finding -Rule "ProgramDuplicate" -Message "$key appears more than once."
    }
    $programs[$key] = $true
}

foreach ($entry in @($observations.OperatorChecks)) {
    if ($null -eq $entry) { continue }
    if (-not $entry.Name -or -not $entry.Prompt) {
        Add-Finding -Rule "OperatorCheckInvalid" -Message "Operator checks must include Name and Prompt."
    }
}

$result = New-Object psobject -Property ([ordered]@{
    Path = (Get-Item -LiteralPath $resolvedObservationPath).FullName
    IsValid = ($findings.Count -eq 0)
    RegisterCount = $registers.Count
    IoSignalCount = $signals.Count
    ProgramPresenceCount = $programs.Count
    OperatorCheckCount = @($observations.OperatorChecks).Count
    Findings = $findings.ToArray()
})

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "Cell observations validation failed for $($result.Path):`n$($messages -join "`n")"
}
