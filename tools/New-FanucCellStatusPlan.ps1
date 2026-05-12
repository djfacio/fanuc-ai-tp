param(
    [string]$ObservationPath = "..\config\cell-observations.psd1",
    [string]$OutputRoot = "generated\cell-status",
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

if ([System.IO.Path]::IsPathRooted($ObservationPath)) {
    $resolvedObservation = Resolve-Path -LiteralPath $ObservationPath
} else {
    $resolvedObservation = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ObservationPath)
}
$resolvedObservationPath = $resolvedObservation.Path

$validator = Join-Path $scriptRoot "Test-FanucCellObservations.ps1"
& $validator -ObservationPath $resolvedObservationPath -Quiet

$observations = Import-PowerShellDataFile -LiteralPath $resolvedObservationPath
$resolvedOutputRoot = Resolve-ProjectPath $OutputRoot
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss")
$planDir = Join-Path $resolvedOutputRoot $stamp
$latestDir = Join-Path $resolvedOutputRoot "latest"

foreach ($path in @($planDir, $latestDir)) {
    if ((Test-Path -LiteralPath $path) -and -not $Force -and $path -eq $latestDir) {
        throw "Latest status plan already exists: $path. Use -Force to overwrite."
    }
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

$planJsonPath = Join-Path $planDir "status-plan.json"
$planMarkdownPath = Join-Path $planDir "status-plan.md"
$latestJsonPath = Join-Path $latestDir "status-plan.json"
$latestMarkdownPath = Join-Path $latestDir "status-plan.md"

$plan = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    observationPath = (Get-Item -LiteralPath $resolvedObservationPath).FullName
    purpose = "Read-only cell status snapshot plan. This artifact does not read or write the robot."
    transports = $observations.Transports
    registers = @($observations.Registers | ForEach-Object {
        [ordered]@{
            address = "R[$($_.Register)]"
            register = [int]$_.Register
            name = $_.Name
            source = $_.Source
            expectedUse = $_.ExpectedUse
        }
    })
    ioSignals = @($observations.IoSignals | ForEach-Object {
        [ordered]@{
            signal = $_.Signal.ToUpperInvariant()
            name = $_.Name
            source = $_.Source
            expectedUse = $_.ExpectedUse
        }
    })
    programPresence = @($observations.ProgramPresence | ForEach-Object {
        [ordered]@{
            program = $_.Program.ToUpperInvariant()
            source = $_.Source
            expectedUse = $_.ExpectedUse
        }
    })
    operatorChecks = @($observations.OperatorChecks | ForEach-Object {
        [ordered]@{
            name = $_.Name
            prompt = $_.Prompt
        }
    })
    nextImplementationChoices = @(
        "SNPX read-only register and IO snapshot",
        "PCDK read-only status snapshot",
        "KAREL TCP read-only status service"
    )
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# FANUC Cell Status Plan")
$lines.Add("")
$lines.Add("Generated: $($plan.generatedAt)")
$lines.Add("")
$lines.Add("This is a read-only planning artifact. It does not read from or write to the robot.")
$lines.Add("")
$lines.Add("## Transport Options")
$lines.Add("")
foreach ($transport in @($observations.Transports.Preferred)) {
    $lines.Add("- $transport")
}
$lines.Add("")
$lines.Add("## Registers To Read")
$lines.Add("")
$lines.Add("| Register | Name | Source | Expected use |")
$lines.Add("| --- | --- | --- | --- |")
foreach ($entry in $plan.registers) {
    $lines.Add("| $($entry.address) | $($entry.name) | $($entry.source) | $($entry.expectedUse) |")
}
$lines.Add("")
$lines.Add("## IO Signals To Read")
$lines.Add("")
$lines.Add("| Signal | Name | Source | Expected use |")
$lines.Add("| --- | --- | --- | --- |")
foreach ($entry in $plan.ioSignals) {
    $lines.Add("| $($entry.signal) | $($entry.name) | $($entry.source) | $($entry.expectedUse) |")
}
$lines.Add("")
$lines.Add("## Program Presence Checks")
$lines.Add("")
$lines.Add("| Program | Source | Expected use |")
$lines.Add("| --- | --- | --- |")
foreach ($entry in $plan.programPresence) {
    $lines.Add("| $($entry.program) | $($entry.source) | $($entry.expectedUse) |")
}
$lines.Add("")
$lines.Add("## Operator Checks")
$lines.Add("")
foreach ($entry in $plan.operatorChecks) {
    $lines.Add("- $($entry.name): $($entry.prompt)")
}
$lines.Add("")
$lines.Add("## Next Implementation")
$lines.Add("")
$lines.Add("Choose one transport and implement reads only. Do not add write behavior from this plan.")

$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $planJsonPath -Encoding ASCII
$lines | Set-Content -LiteralPath $planMarkdownPath -Encoding ASCII
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $latestJsonPath -Encoding ASCII
$lines | Set-Content -LiteralPath $latestMarkdownPath -Encoding ASCII

[pscustomobject]@{
    GeneratedAt = $plan.generatedAt
    RegisterCount = @($plan.registers).Count
    IoSignalCount = @($plan.ioSignals).Count
    ProgramPresenceCount = @($plan.programPresence).Count
    OperatorCheckCount = @($plan.operatorChecks).Count
    PlanDirectory = (Get-Item -LiteralPath $planDir).FullName
    PlanMarkdownPath = (Get-Item -LiteralPath $planMarkdownPath).FullName
    LatestMarkdownPath = (Get-Item -LiteralPath $latestMarkdownPath).FullName
}
