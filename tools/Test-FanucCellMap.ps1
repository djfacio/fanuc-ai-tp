param(
    [string]$CellMapPath = "..\config\cell-map.psd1",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([System.IO.Path]::IsPathRooted($CellMapPath)) {
    $resolvedCellMap = Resolve-Path -LiteralPath $CellMapPath
} else {
    $resolvedCellMap = Resolve-Path -LiteralPath (Join-Path $scriptRoot $CellMapPath)
}
$resolvedCellMapPath = $resolvedCellMap.Path

$cellMap = Import-PowerShellDataFile -LiteralPath $resolvedCellMapPath
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

if ([int]$cellMap.SchemaVersion -ne 1) {
    Add-Finding -Rule "SchemaVersion" -Message "Cell map SchemaVersion must be 1."
}

if (-not $cellMap.PolicyScope -or $cellMap.PolicyScope.Trim().Length -eq 0) {
    Add-Finding -Rule "PolicyScopeRequired" -Message "Cell map must declare PolicyScope so policies do not carry across projects implicitly."
}

foreach ($requiredName in @("ProjectName", "WorkcellName")) {
    if (-not $cellMap.$requiredName -or $cellMap.$requiredName.Trim().Length -eq 0) {
        Add-Finding -Rule "$($requiredName)Required" -Message "Cell map must declare $requiredName."
    }
}

$registers = @{}
$registerRanges = New-Object System.Collections.Generic.List[object]
foreach ($range in @($cellMap.RegisterWrites.AllowedRanges)) {
    if ($null -eq $range) {
        continue
    }

    if ($null -eq $range.Start -or $null -eq $range.End -or [int]$range.Start -lt 1 -or [int]$range.End -lt [int]$range.Start) {
        Add-Finding -Rule "RegisterRangeInvalid" -Message "Register write ranges must include Start >= 1 and End >= Start."
        continue
    }

    $registerRanges.Add([pscustomobject]@{
        Start = [int]$range.Start
        End = [int]$range.End
    })
}

foreach ($entry in @($cellMap.RegisterWrites.Allowed)) {
    if ($null -eq $entry) {
        continue
    }

    if ($null -eq $entry.Register -or [int]$entry.Register -lt 1) {
        Add-Finding -Rule "RegisterEntryInvalid" -Message "Register write entries must include Register >= 1."
        continue
    }

    $key = [int]$entry.Register
    if ($registers.ContainsKey($key)) {
        Add-Finding -Rule "RegisterDuplicate" -Message "Register R[$key] appears more than once."
    }
    $registers[$key] = $true
}

$signals = @{}
$signalRanges = New-Object System.Collections.Generic.List[object]
foreach ($range in @($cellMap.IoWrites.AllowedRanges)) {
    if ($null -eq $range) {
        continue
    }

    if (-not $range.Type -or $range.Type -notin @("DO", "RO")) {
        Add-Finding -Rule "SignalRangeTypeInvalid" -Message "IO write ranges must include Type DO or RO."
        continue
    }

    if ($null -eq $range.Start -or $null -eq $range.End -or [int]$range.Start -lt 1 -or [int]$range.End -lt [int]$range.Start) {
        Add-Finding -Rule "SignalRangeInvalid" -Message "IO write ranges must include Start >= 1 and End >= Start."
        continue
    }

    if ($range.SafeStates) {
        foreach ($state in @($range.SafeStates)) {
            if ($state.ToUpperInvariant() -notin @("ON", "OFF")) {
                Add-Finding -Rule "SignalRangeStateInvalid" -Message "IO write range '$($range.Type)[$($range.Start)-$($range.End)]' has invalid SafeState '$state'."
            }
        }
    }

    $signalRanges.Add([pscustomobject]@{
        Type = $range.Type.ToUpperInvariant()
        Start = [int]$range.Start
        End = [int]$range.End
    })
}

foreach ($entry in @($cellMap.IoWrites.Allowed)) {
    if ($null -eq $entry) {
        continue
    }

    if (-not $entry.Signal -or $entry.Signal -notmatch '^(DO|RO)\[[1-9][0-9]*\]$') {
        Add-Finding -Rule "SignalEntryInvalid" -Message "IO write entries must include Signal like DO[1] or RO[1]."
        continue
    }

    $key = $entry.Signal.ToUpperInvariant()
    if ($signals.ContainsKey($key)) {
        Add-Finding -Rule "SignalDuplicate" -Message "$key appears more than once."
    }
    $signals[$key] = $true
}

$calls = @{}
foreach ($entry in @($cellMap.Calls.Allowed)) {
    if ($null -eq $entry) {
        continue
    }

    if (-not $entry.Program -or $entry.Program -cnotmatch '^[A-Z][A-Z0-9_]{0,31}$') {
        Add-Finding -Rule "CallEntryInvalid" -Message "CALL entries must include an uppercase FANUC-compatible Program name."
        continue
    }

    $key = $entry.Program.ToUpperInvariant()
    if ($calls.ContainsKey($key)) {
        Add-Finding -Rule "CallDuplicate" -Message "$key appears more than once."
    }
    $calls[$key] = $true
}

$result = New-Object psobject -Property ([ordered]@{
    Path = (Get-Item -LiteralPath $resolvedCellMapPath).FullName
    IsValid = ($findings.Count -eq 0)
    RegisterWriteCount = $registers.Count
    RegisterWriteRangeCount = $registerRanges.Count
    IoWriteCount = $signals.Count
    IoWriteRangeCount = $signalRanges.Count
    CallTargetCount = $calls.Count
    Findings = $findings.ToArray()
})

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "Cell map validation failed for $($result.Path):`n$($messages -join "`n")"
}
