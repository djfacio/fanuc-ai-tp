param(
    [string]$PlanPath = "generated\cell-status\latest\status-plan.json",
    [string]$ValuesPath,
    [string]$Label = "manual",
    [string]$OutputRoot = "generated\cell-status\snapshots",
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

function Get-ValueByName {
    param(
        [object]$Object,
        [string]$Name
    )

    if ($null -eq $Object) {
        return $null
    }
    if ($Object.PSObject.Properties.Name -contains $Name) {
        return $Object.$Name
    }
    return $null
}

$resolvedPlanPath = Resolve-ProjectPath $PlanPath
if (-not (Test-Path -LiteralPath $resolvedPlanPath)) {
    throw "Status plan not found: $resolvedPlanPath. Run New-FanucCellStatusPlan.ps1 first."
}

$values = $null
if ($ValuesPath) {
    $resolvedValuesPath = Resolve-ProjectPath $ValuesPath
    if (-not (Test-Path -LiteralPath $resolvedValuesPath)) {
        throw "Values file not found: $resolvedValuesPath"
    }
    $values = Get-Content -LiteralPath $resolvedValuesPath -Raw | ConvertFrom-Json
}

$plan = Get-Content -LiteralPath $resolvedPlanPath -Raw | ConvertFrom-Json
$safeLabel = ($Label -replace '[^A-Za-z0-9_\-]', '_')
if ($safeLabel.Length -eq 0) {
    $safeLabel = "manual"
}

$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$resolvedOutputRoot = Resolve-ProjectPath $OutputRoot
$snapshotDir = Join-Path $resolvedOutputRoot ("{0}-{1}" -f $stamp, $safeLabel)
$snapshotJsonPath = Join-Path $snapshotDir "snapshot.json"
$snapshotMarkdownPath = Join-Path $snapshotDir "snapshot.md"

if ((Test-Path -LiteralPath $snapshotDir) -and -not $Force) {
    throw "Snapshot directory already exists: $snapshotDir. Use -Force to overwrite."
}
if (-not (Test-Path -LiteralPath $snapshotDir)) {
    New-Item -ItemType Directory -Path $snapshotDir -Force | Out-Null
}

$registerValues = Get-ValueByName -Object $values -Name "registers"
$ioValues = Get-ValueByName -Object $values -Name "ioSignals"
$programValues = Get-ValueByName -Object $values -Name "programPresence"
$operatorValues = Get-ValueByName -Object $values -Name "operatorChecks"

$snapshot = [ordered]@{
    schemaVersion = 1
    capturedAt = (Get-Date).ToString("o")
    label = $Label
    source = if ($ValuesPath) { "values-file" } else { "manual-template" }
    planPath = (Get-Item -LiteralPath $resolvedPlanPath).FullName
    valuesPath = if ($ValuesPath) { (Get-Item -LiteralPath $resolvedValuesPath).FullName } else { $null }
    registers = @($plan.registers | ForEach-Object {
        $address = $_.address
        [ordered]@{
            address = $address
            name = $_.name
            value = Get-ValueByName -Object $registerValues -Name $address
            source = $_.source
            expectedUse = $_.expectedUse
        }
    })
    ioSignals = @($plan.ioSignals | ForEach-Object {
        $signal = $_.signal
        [ordered]@{
            signal = $signal
            name = $_.name
            state = Get-ValueByName -Object $ioValues -Name $signal
            source = $_.source
            expectedUse = $_.expectedUse
        }
    })
    programPresence = @($plan.programPresence | ForEach-Object {
        $program = $_.program
        [ordered]@{
            program = $program
            present = Get-ValueByName -Object $programValues -Name $program
            source = $_.source
            expectedUse = $_.expectedUse
        }
    })
    operatorChecks = @($plan.operatorChecks | ForEach-Object {
        $name = $_.name
        [ordered]@{
            name = $name
            prompt = $_.prompt
            value = Get-ValueByName -Object $operatorValues -Name $name
        }
    })
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# FANUC Cell Status Snapshot")
$lines.Add("")
$lines.Add("Captured: $($snapshot.capturedAt)")
$lines.Add("")
$lines.Add("- Label: $Label")
$lines.Add("- Source: $($snapshot.source)")
$lines.Add("- Plan: $($snapshot.planPath)")
$lines.Add("")
$lines.Add("## Registers")
$lines.Add("")
$lines.Add("| Register | Value | Name |")
$lines.Add("| --- | --- | --- |")
foreach ($entry in $snapshot.registers) {
    $value = if ($null -ne $entry.value) { $entry.value } else { "" }
    $lines.Add("| $($entry.address) | $value | $($entry.name) |")
}
$lines.Add("")
$lines.Add("## IO Signals")
$lines.Add("")
$lines.Add("| Signal | State | Name |")
$lines.Add("| --- | --- | --- |")
foreach ($entry in $snapshot.ioSignals) {
    $value = if ($null -ne $entry.state) { $entry.state } else { "" }
    $lines.Add("| $($entry.signal) | $value | $($entry.name) |")
}
$lines.Add("")
$lines.Add("## Program Presence")
$lines.Add("")
$lines.Add("| Program | Present | Expected use |")
$lines.Add("| --- | --- | --- |")
foreach ($entry in $snapshot.programPresence) {
    $value = if ($null -ne $entry.present) { $entry.present } else { "" }
    $lines.Add("| $($entry.program) | $value | $($entry.expectedUse) |")
}
$lines.Add("")
$lines.Add("## Operator Checks")
$lines.Add("")
foreach ($entry in $snapshot.operatorChecks) {
    $value = if ($null -ne $entry.value) { $entry.value } else { "" }
    $lines.Add("- $($entry.name): $value")
    $lines.Add("  - Prompt: $($entry.prompt)")
}

$snapshot | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $snapshotJsonPath -Encoding ASCII
$lines | Set-Content -LiteralPath $snapshotMarkdownPath -Encoding ASCII

[pscustomobject]@{
    Label = $Label
    Source = $snapshot.source
    RegisterCount = @($snapshot.registers).Count
    IoSignalCount = @($snapshot.ioSignals).Count
    ProgramPresenceCount = @($snapshot.programPresence).Count
    OperatorCheckCount = @($snapshot.operatorChecks).Count
    SnapshotPath = (Get-Item -LiteralPath $snapshotJsonPath).FullName
    SnapshotMarkdownPath = (Get-Item -LiteralPath $snapshotMarkdownPath).FullName
}
