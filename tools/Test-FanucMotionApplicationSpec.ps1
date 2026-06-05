param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$SchemaPath = "..\schemas\motion-application-spec.schema.json",
    [string]$CellMapPath = "..\config\cell-map.psd1",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    $scriptRelative = Join-Path $scriptRoot $Path
    if (Test-Path -LiteralPath $scriptRelative) {
        return (Resolve-Path -LiteralPath $scriptRelative).Path
    }
    return (Resolve-Path -LiteralPath (Join-Path $projectRoot $Path)).Path
}

$resolvedSpec = Resolve-Path -LiteralPath $SpecPath
$resolvedSchema = Resolve-ProjectPath $SchemaPath
$resolvedCellMap = Resolve-ProjectPath $CellMapPath
$schemaValidator = Join-Path $scriptRoot "Test-FanucJsonSchema.ps1"
$cellMapValidator = Join-Path $scriptRoot "Test-FanucCellMap.ps1"
& $cellMapValidator -CellMapPath $resolvedCellMap -Quiet
$cellMap = Import-PowerShellDataFile -LiteralPath $resolvedCellMap

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

function Test-AllowedIoWrite {
    param(
        [string]$Signal,
        [bool]$State
    )

    $stateText = if ($State) { "ON" } else { "OFF" }
    $normalizedSignal = $Signal.ToUpperInvariant()
    foreach ($entry in @($cellMap.IoWrites.Allowed)) {
        if ($entry.Signal.ToUpperInvariant() -ne $normalizedSignal) {
            continue
        }

        if ($null -eq $entry.SafeStates -or @($entry.SafeStates).Count -eq 0) {
            return $true
        }

        return (@($entry.SafeStates | ForEach-Object { $_.ToUpperInvariant() }) -contains $stateText)
    }

    if ($normalizedSignal -match '^(DO|RO)\[(\d+)\]$') {
        $signalType = $Matches[1]
        $signalNumber = [int]$Matches[2]
        foreach ($range in @($cellMap.IoWrites.AllowedRanges)) {
            if ($range.Type.ToUpperInvariant() -ne $signalType) {
                continue
            }
            if ($signalNumber -lt [int]$range.Start -or $signalNumber -gt [int]$range.End) {
                continue
            }

            if ($null -eq $range.SafeStates -or @($range.SafeStates).Count -eq 0) {
                return $true
            }

            return (@($range.SafeStates | ForEach-Object { $_.ToUpperInvariant() }) -contains $stateText)
        }
    }

    return $false
}

function Test-AllowedRegisterWrite {
    param([int]$Register)

    foreach ($entry in @($cellMap.RegisterWrites.Allowed)) {
        if ([int]$entry.Register -eq $Register) {
            return $true
        }
    }

    foreach ($range in @($cellMap.RegisterWrites.AllowedRanges)) {
        if ($Register -ge [int]$range.Start -and $Register -le [int]$range.End) {
            return $true
        }
    }

    return $false
}

function Test-AllowedCallTarget {
    param([string]$Program)

    $normalizedProgram = $Program.ToUpperInvariant()
    foreach ($entry in @($cellMap.Calls.Allowed)) {
        if ($entry.Program.ToUpperInvariant() -eq $normalizedProgram) {
            return $true
        }
    }

    return $false
}

try {
    & $schemaValidator -JsonPath $resolvedSpec -SchemaPath $resolvedSchema -Quiet
} catch {
    Add-Finding -Rule "JsonSchema" -Message $_.Exception.Message
}

$spec = Get-Content -LiteralPath $resolvedSpec -Raw | ConvertFrom-Json

if ($spec.policy.productionOverwriteAllowed) {
    Add-Finding -Rule "ProductionOverwriteBlocked" -Message "Motion application specs must not allow production overwrite."
}

if (-not $spec.policy.humanReviewRequired) {
    Add-Finding -Rule "HumanReviewRequired" -Message "Motion application specs must require human review."
}

$readyGateFindings = New-Object System.Collections.Generic.List[object]
function Add-ReadyGate {
    param([string]$Message)
    $readyGateFindings.Add($Message)
}

if ($spec.policy.motionAuthority -ne "reviewed-motion-template" -and $spec.policy.motionAuthority -ne "reviewed-application") {
    Add-ReadyGate -Message "motionAuthority must be reviewed-motion-template or reviewed-application."
}
if (-not $spec.resources.userFrame.verified) {
    Add-ReadyGate -Message "userFrame must be verified."
}
if (-not $spec.resources.userTool.verified) {
    Add-ReadyGate -Message "userTool must be verified."
}
if (-not $spec.resources.payload.verified) {
    Add-ReadyGate -Message "payload must be verified."
}
foreach ($point in @($spec.resources.points)) {
    if (-not $point.verified) {
        Add-ReadyGate -Message "point '$($point.name)' must be verified."
    }
}
$reviewedPointNames = @{}
foreach ($point in @($spec.resources.points)) {
    if ($point.name) {
        $reviewedPointNames[$point.name.ToUpperInvariant()] = [bool]$point.verified
    }
}
if (@($spec.motionPlan.motionSequence).Count -lt 1) {
    Add-ReadyGate -Message "motionPlan.motionSequence must include at least one reviewed PR waypoint."
}
foreach ($step in @($spec.motionPlan.motionSequence)) {
    if ($step.motionType -notin @($spec.motionPlan.motionTypes)) {
        Add-ReadyGate -Message "motion step '$($step.stepName)' uses motionType '$($step.motionType)' not declared in motionTypes."
    }
    if ($step.target.type -ne "position-register") {
        Add-ReadyGate -Message "motion step '$($step.stepName)' must use a position-register target."
    }
    if (-not $step.target.verified) {
        Add-ReadyGate -Message "motion step '$($step.stepName)' target '$($step.target.name)' must be verified."
    }
    $targetName = if ($step.target.name) { $step.target.name.ToUpperInvariant() } else { "" }
    if (-not $reviewedPointNames.ContainsKey($targetName)) {
        Add-ReadyGate -Message "motion step '$($step.stepName)' target '$($step.target.name)' must exist in resources.points."
    } elseif (-not $reviewedPointNames[$targetName]) {
        Add-ReadyGate -Message "motion step '$($step.stepName)' target '$($step.target.name)' must reference a verified resources.points entry."
    }
    if ($step.termination.type -eq "CNT" -and $null -eq $step.termination.value) {
        Add-ReadyGate -Message "motion step '$($step.stepName)' uses CNT termination and must include a CNT value."
    }
    if ($step.termination.type -eq "FINE" -and $null -ne $step.termination.value) {
        Add-ReadyGate -Message "motion step '$($step.stepName)' uses FINE termination and must not include a CNT value."
    }
}
foreach ($gate in @("dcsReviewed", "interlocksReviewed", "operatorLocationReviewed", "faultHandlingReviewed", "noControllerConfigWrites")) {
    if (-not [bool]$spec.safety.$gate) {
        Add-ReadyGate -Message "safety.$gate must be true."
    }
}
if (-not $spec.generation.templateId -or $spec.generation.templateId.Trim().Length -eq 0) {
    Add-ReadyGate -Message "generation.templateId must name a reviewed motion template."
}
if ($spec.generation.mode -ne "reviewed-motion-template") {
    Add-ReadyGate -Message "generation.mode must be reviewed-motion-template."
}
$supportedTemplates = @("pr-waypoint-sequence-v1", "approach-process-retract-v1", "io-motion-sequence-v1", "motion-action-calc-pr-v1")
if ($spec.generation.templateId -and $supportedTemplates -notcontains $spec.generation.templateId) {
    Add-ReadyGate -Message "generation.templateId must be one of: $($supportedTemplates -join ', ')."
}

$motionStepNames = @($spec.motionPlan.motionSequence | ForEach-Object { $_.stepName.ToUpperInvariant() })
if ($spec.generation.templateId -eq "approach-process-retract-v1") {
    foreach ($requiredStepName in @("APPROACH", "PROCESS", "RETRACT")) {
        if ($motionStepNames -notcontains $requiredStepName) {
            Add-ReadyGate -Message "approach-process-retract-v1 requires a $requiredStepName motion step."
        }
    }
}

$ioSequence = @()
if ($null -ne $spec.motionPlan.PSObject.Properties["ioSequence"]) {
    $ioSequence = @($spec.motionPlan.ioSequence)
}
if ($spec.generation.templateId -eq "io-motion-sequence-v1" -and $ioSequence.Count -lt 1) {
    Add-ReadyGate -Message "io-motion-sequence-v1 requires at least one motionPlan.ioSequence action."
}
if ($spec.generation.templateId -ne "io-motion-sequence-v1" -and $ioSequence.Count -gt 0) {
    Add-ReadyGate -Message "motionPlan.ioSequence is only supported by io-motion-sequence-v1."
}
foreach ($ioAction in $ioSequence) {
    $ioStepName = $ioAction.stepName.ToUpperInvariant()
    if ($motionStepNames -notcontains $ioStepName) {
        Add-ReadyGate -Message "IO action for step '$($ioAction.stepName)' must reference a motionSequence step."
    }
    if (-not [bool]$ioAction.verified) {
        Add-ReadyGate -Message "IO action '$($ioAction.signal)' at step '$($ioAction.stepName)' must be verified."
    }
    if (-not (Test-AllowedIoWrite -Signal $ioAction.signal -State ([bool]$ioAction.state))) {
        Add-ReadyGate -Message "IO action writes $($ioAction.signal), which is not allowed by config\cell-map.psd1."
    }
}

if ($spec.generation.templateId -eq "motion-action-calc-pr-v1") {
    if ($null -eq $spec.motionPlan.PSObject.Properties["positionArchitecture"]) {
        Add-ReadyGate -Message "motion-action-calc-pr-v1 requires motionPlan.positionArchitecture."
    } else {
        $architecture = $spec.motionPlan.positionArchitecture
        if ($architecture.strategy -ne "explicit-calculated-prs") {
            Add-ReadyGate -Message "motion-action-calc-pr-v1 requires positionArchitecture.strategy='explicit-calculated-prs'."
        }

        if (-not [bool]$architecture.calcProgram.required) {
            Add-ReadyGate -Message "motion-action-calc-pr-v1 requires a CALC_POS-style program contract."
        }
        if (-not [bool]$architecture.calcProgram.verified) {
            Add-ReadyGate -Message "positionArchitecture.calcProgram must be verified."
        }
        if (-not [bool]$architecture.calcProgram.callBeforeMotion -and ([string]::IsNullOrWhiteSpace([string]$architecture.calcProgram.notes))) {
            Add-ReadyGate -Message "If calcProgram.callBeforeMotion is false, calcProgram.notes must state who calculated the PRs before motion."
        }
        if ([bool]$architecture.calcProgram.callBeforeMotion -and -not (Test-AllowedCallTarget -Program ([string]$architecture.calcProgram.programName))) {
            Add-ReadyGate -Message "Calc program '$($architecture.calcProgram.programName)' must be allowlisted in config\cell-map.psd1 before the generated motion program may call it."
        }

        foreach ($family in @($architecture.prFamilies)) {
            if (-not [bool]$family.verified) {
                Add-ReadyGate -Message "PR family '$($family.familyName)' must be verified."
            }
        }

        $offsetPrNumbers = @{}
        foreach ($offsetPr in @($architecture.offsetPrs)) {
            $offsetPrNumbers[[int]$offsetPr.number] = $true
            if (-not [bool]$offsetPr.verified) {
                Add-ReadyGate -Message "Offset PR[$([int]$offsetPr.number):$($offsetPr.name)] must be verified."
            }
            if ([bool]$offsetPr.aiMayPopulate -and $null -eq $offsetPr.PSObject.Properties["zeroingMethod"]) {
                Add-ReadyGate -Message "Offset PR[$([int]$offsetPr.number):$($offsetPr.name)] allows AI population and must declare zeroingMethod."
            }
        }

        $fixedPrNumbers = @{}
        foreach ($fixedPr in @($architecture.fixedPrs)) {
            $fixedPrNumbers[[int]$fixedPr.number] = $true
            if (-not [bool]$fixedPr.verified) {
                Add-ReadyGate -Message "Fixed PR[$([int]$fixedPr.number):$($fixedPr.name)] must be verified."
            }
        }

        $derivedPrNumbers = @{}
        foreach ($derivedPr in @($architecture.derivedPrs)) {
            $derivedPrNumbers[[int]$derivedPr.number] = $true
            if (-not [bool]$derivedPr.verified) {
                Add-ReadyGate -Message "Derived PR[$([int]$derivedPr.number):$($derivedPr.name)] must be verified."
            }
            if (-not [bool]$derivedPr.availableForPendantMoveTo) {
                Add-ReadyGate -Message "Derived PR[$([int]$derivedPr.number):$($derivedPr.name)] must be available for pendant MOVE_TO/touchup review."
            }
            if (-not $offsetPrNumbers.ContainsKey([int]$derivedPr.sourceOffsetPr)) {
                Add-ReadyGate -Message "Derived PR[$([int]$derivedPr.number):$($derivedPr.name)] references missing offset PR[$([int]$derivedPr.sourceOffsetPr)]."
            }
        }

        foreach ($step in @($spec.motionPlan.motionSequence)) {
            $targetNumber = [int]$step.target.number
            if (-not $derivedPrNumbers.ContainsKey($targetNumber) -and -not $fixedPrNumbers.ContainsKey($targetNumber)) {
                Add-ReadyGate -Message "motion-action-calc-pr-v1 target PR[$targetNumber] must be listed in positionArchitecture.derivedPrs or fixedPrs."
            }
        }

        if ([bool]$architecture.inlineOffsetPolicy.defaultAllowed) {
            Add-ReadyGate -Message "Inline Offset,PR[] / Tool_Offset,PR[] must not be default-allowed for motion-action-calc-pr-v1."
        }
        foreach ($exception in @($architecture.inlineOffsetPolicy.exceptions)) {
            if (-not [bool]$exception.reviewed) {
                Add-ReadyGate -Message "Inline offset exception for step '$($exception.stepName)' must be reviewed."
            }
            if ($motionStepNames -notcontains $exception.stepName.ToUpperInvariant()) {
                Add-ReadyGate -Message "Inline offset exception for step '$($exception.stepName)' must reference a motionSequence step."
            }
        }

        if (-not [bool]$architecture.breadcrumb.enabled) {
            Add-ReadyGate -Message "motion-action-calc-pr-v1 requires breadcrumb.enabled=true."
        }
        if ($architecture.breadcrumb.assignmentPosition -ne "after-motion") {
            Add-ReadyGate -Message "Breadcrumb assignmentPosition must be after-motion for this project convention."
        }
        if ($architecture.breadcrumb.semantics -ne "last-motion-statement-advanced-past") {
            Add-ReadyGate -Message "Breadcrumb semantics must be last-motion-statement-advanced-past, not actual robot position."
        }
        if (-not [bool]$architecture.breadcrumb.requiredForEveryMotion) {
            Add-ReadyGate -Message "Breadcrumb must be required for every motion."
        }
        if (-not (Test-AllowedRegisterWrite -Register ([int]$architecture.breadcrumb.register))) {
            Add-ReadyGate -Message "Breadcrumb register R[$([int]$architecture.breadcrumb.register)] is not allowed by config\cell-map.psd1."
        }
    }
}

$readyForGeneration = ($readyGateFindings.Count -eq 0)
if ($spec.generation.allowed -and -not $readyForGeneration) {
    foreach ($message in $readyGateFindings.ToArray()) {
        Add-Finding -Rule "GenerationGate" -Message $message
    }
}
if ($spec.phase -in @("generation-ready", "generated", "uploaded", "operator-released", "released") -and -not $readyForGeneration) {
    foreach ($message in $readyGateFindings.ToArray()) {
        Add-Finding -Rule "PhaseGate" -Message $message
    }
}

$result = [pscustomobject]@{
    Path = (Get-Item -LiteralPath $resolvedSpec).FullName
    ProgramName = $spec.programName
    Phase = $spec.phase
    IsValid = ($findings.Count -eq 0)
    ReadyForGeneration = $readyForGeneration
    FindingCount = $findings.Count
    Findings = $findings.ToArray()
    GenerationGateMessages = $readyGateFindings.ToArray()
}

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "Motion application spec validation failed for $($result.Path):`n$($messages -join "`n")"
}
