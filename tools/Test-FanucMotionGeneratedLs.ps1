param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [Parameter(Mandatory = $true)]
    [string]$LsPath,

    [string]$CellMapPath = "..\config\cell-map.psd1",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

function Resolve-InputPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return (Resolve-Path -LiteralPath (Join-Path $scriptRoot $Path)).Path
}

function Format-FanucNumber {
    param([double]$Value)

    return $Value.ToString("0.###", [System.Globalization.CultureInfo]::InvariantCulture)
}

function Format-FanucSpeed {
    param($Speed)

    $value = Format-FanucNumber ([double]$Speed.value)
    switch ($Speed.unit) {
        "%" { return "$value%" }
        "mm/sec" { return "${value}MM/SEC" }
        "cm/min" { return "${value}CM/MIN" }
        "deg/sec" { return "${value}DEG/SEC" }
        default { throw "Unsupported speed unit '$($Speed.unit)'." }
    }
}

function Format-FanucTermination {
    param($Termination)

    if ($Termination.type -eq "FINE") {
        return "FINE"
    }
    return "CNT$([int]$Termination.value)"
}

function Get-NormalizedMnInstructions {
    param([string]$Path)

    $text = Get-Content -LiteralPath $Path -Raw
    $match = [regex]::Match($text, '(?is)/MN\s*(.*?)\s*/POS')
    if (-not $match.Success) {
        throw "Could not find /MN section in $Path"
    }

    $instructions = New-Object System.Collections.Generic.List[string]
    foreach ($line in ($match.Groups[1].Value -split '\r?\n')) {
        $normalized = $line.Trim()
        if ($normalized.Length -eq 0) {
            continue
        }

        $normalized = [regex]::Replace($normalized, '^\d+\s*:\s*', '')
        $normalized = [regex]::Replace($normalized, '\s+', ' ')
        $normalized = [regex]::Replace($normalized, '(?i)\bPR\[(\d+)\s*:\s*[^\]]+\]', 'PR[$1]')
        $normalized = [regex]::Replace($normalized, '\s*=\s*', '=')
        $normalized = [regex]::Replace($normalized, '\s*;\s*$', ' ;')
        $instructions.Add($normalized.Trim().ToUpperInvariant())
    }

    return $instructions.ToArray()
}

$resolvedSpecPath = Resolve-InputPath -Path $SpecPath
$resolvedLsPath = Resolve-InputPath -Path $LsPath
$specValidator = Join-Path $scriptRoot "Test-FanucMotionApplicationSpec.ps1"

& $specValidator -SpecPath $resolvedSpecPath -CellMapPath $CellMapPath -Quiet

$spec = Get-Content -LiteralPath $resolvedSpecPath -Raw | ConvertFrom-Json
$lsText = Get-Content -LiteralPath $resolvedLsPath -Raw
$instructions = @(Get-NormalizedMnInstructions -Path $resolvedLsPath)
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

$programMatch = [regex]::Match($lsText, '(?im)^\s*/PROG\s+([A-Za-z][A-Za-z0-9_]*)\s*$')
if (-not $programMatch.Success) {
    Add-Finding -Rule "ProgramHeaderMissing" -Message "Generated LS must include a /PROG header."
} elseif ($programMatch.Groups[1].Value.ToUpperInvariant() -ne $spec.programName.ToUpperInvariant()) {
    Add-Finding -Rule "ProgramMismatch" -Message "Generated LS program '$($programMatch.Groups[1].Value)' does not match spec '$($spec.programName)'."
}

$expectedInstructions = New-Object System.Collections.Generic.List[string]
$expectedInstructions.Add("PAYLOAD[$([int]$spec.resources.payload.number)] ;")

$templateId = [string]$spec.generation.templateId
if ($templateId -ne "motion-action-calc-pr-v1") {
    $expectedInstructions.Add("UFRAME_NUM=$([int]$spec.resources.userFrame.number) ;")
    $expectedInstructions.Add("UTOOL_NUM=$([int]$spec.resources.userTool.number) ;")
} elseif ([bool]$spec.motionPlan.positionArchitecture.calcProgram.required -and [bool]$spec.motionPlan.positionArchitecture.calcProgram.callBeforeMotion) {
    $expectedInstructions.Add("CALL $($spec.motionPlan.positionArchitecture.calcProgram.programName.ToUpperInvariant()) ;")
}

$expectedMoves = New-Object System.Collections.Generic.List[string]
foreach ($step in @($spec.motionPlan.motionSequence)) {
    $speed = Format-FanucSpeed $step.speed
    $termination = Format-FanucTermination $step.termination
    $move = "$($step.motionType.ToUpperInvariant()) PR[$([int]$step.target.number)] $speed $termination ;"
    if ($templateId -eq "motion-action-calc-pr-v1") {
        $expectedInstructions.Add("UFRAME_NUM=$([int]$spec.resources.userFrame.number) ;")
        $expectedInstructions.Add("UTOOL_NUM=$([int]$spec.resources.userTool.number) ;")
    }
    $expectedInstructions.Add($move)
    $expectedMoves.Add($move)
    if ($templateId -eq "motion-action-calc-pr-v1") {
        $expectedInstructions.Add("R[$([int]$spec.motionPlan.positionArchitecture.breadcrumb.register)]=$([int]$step.target.number) ;")
    }
}

if ($null -ne $spec.motionPlan.PSObject.Properties["ioSequence"]) {
    foreach ($ioAction in @($spec.motionPlan.ioSequence)) {
        $state = if ([bool]$ioAction.state) { "ON" } else { "OFF" }
        $expectedInstructions.Add("$($ioAction.signal.ToUpperInvariant())=$state ;")
    }
}

$actualMotionInstructions = @($instructions | Where-Object { $_ -match '^(J|L)\s+PR\[[0-9]+\]\s+' })
$actualIoInstructions = @($instructions | Where-Object { $_ -match '^(DO|RO)\[[0-9]+\]=(ON|OFF)\s+;' })
$actualRegisterInstructions = @($instructions | Where-Object { $_ -match '^R\[[0-9]+\]=[-]?[0-9]+(\.[0-9]+)?\s+;' })
foreach ($expected in @($expectedInstructions.ToArray())) {
    if ($instructions -notcontains $expected.ToUpperInvariant()) {
        Add-Finding -Rule "ExpectedInstructionMissing" -Message "Generated LS is missing expected instruction: $expected"
    }
}

$unexpectedMotion = @($actualMotionInstructions | Where-Object { @($expectedMoves.ToArray() | ForEach-Object { $_.ToUpperInvariant() }) -notcontains $_ })
foreach ($motion in $unexpectedMotion) {
    Add-Finding -Rule "UnexpectedMotionInstruction" -Message "Generated LS includes motion not present in spec: $motion"
}

$expectedIoInstructions = @()
if ($null -ne $spec.motionPlan.PSObject.Properties["ioSequence"]) {
    $expectedIoInstructions = @($spec.motionPlan.ioSequence | ForEach-Object {
        $state = if ([bool]$_.state) { "ON" } else { "OFF" }
        "$($_.signal.ToUpperInvariant())=$state ;"
    })
}
$unexpectedIo = @($actualIoInstructions | Where-Object { @($expectedIoInstructions | ForEach-Object { $_.ToUpperInvariant() }) -notcontains $_ })
foreach ($io in $unexpectedIo) {
    Add-Finding -Rule "UnexpectedIoInstruction" -Message "Generated LS includes IO not present in spec: $io"
}

if ($templateId -eq "motion-action-calc-pr-v1") {
    $expectedBreadcrumbs = @($spec.motionPlan.motionSequence | ForEach-Object {
        "R[$([int]$spec.motionPlan.positionArchitecture.breadcrumb.register)]=$([int]$_.target.number) ;"
    })
    $unexpectedRegister = @($actualRegisterInstructions | Where-Object { @($expectedBreadcrumbs | ForEach-Object { $_.ToUpperInvariant() }) -notcontains $_ })
    foreach ($registerWrite in $unexpectedRegister) {
        Add-Finding -Rule "UnexpectedRegisterInstruction" -Message "Generated LS includes register write not present in spec breadcrumb contract: $registerWrite"
    }
} elseif ($actualRegisterInstructions.Count -gt 0) {
    foreach ($registerWrite in $actualRegisterInstructions) {
        Add-Finding -Rule "UnexpectedRegisterInstruction" -Message "Generated LS includes register write not supported by this motion template: $registerWrite"
    }
}

if ($lsText -match '(?im)^\s*P\[[0-9]+') {
    Add-Finding -Rule "GeneratedPositionRecordsBlocked" -Message "First PR-waypoint motion template must not emit generated /POS position records."
}

$result = [pscustomobject]@{
    SpecPath = (Get-Item -LiteralPath $resolvedSpecPath).FullName
    LsPath = (Get-Item -LiteralPath $resolvedLsPath).FullName
    ProgramName = $spec.programName.ToUpperInvariant()
    IsValid = ($findings.Count -eq 0)
    ExpectedInstructions = $expectedInstructions.ToArray()
    ActualMotionInstructions = $actualMotionInstructions
    ActualIoInstructions = $actualIoInstructions
    ActualRegisterInstructions = $actualRegisterInstructions
    FindingCount = $findings.Count
    Findings = $findings.ToArray()
}

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "Motion generated LS validation failed for $($result.LsPath):`n$($messages -join "`n")"
}
