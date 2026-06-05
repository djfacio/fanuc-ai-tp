param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,31}$')]
    [string]$ProgramName,

    [string]$OutputRoot = "generated"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $resolvedOutputRoot = $OutputRoot
} else {
    $resolvedOutputRoot = Join-Path $projectRoot $OutputRoot
}
$program = $ProgramName.ToUpperInvariant()
$jobDir = Join-Path (Join-Path $resolvedOutputRoot "jobs") $program
$manifestPath = Join-Path $jobDir "manifest.json"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
$motionSpec = $null
if ($null -ne $manifest.files.motionApplicationSpec -and [bool]$manifest.files.motionApplicationSpec.exists) {
    $motionSpec = Get-Content -LiteralPath $manifest.files.motionApplicationSpec.path -Raw | ConvertFrom-Json
}

function Format-FileLine {
    param(
        [string]$Label,
        [object]$Record
    )

    if ($null -eq $Record -or -not [bool]$Record.exists) {
        return "- ${Label}: missing"
    }

    return "- ${Label}: $($Record.path) [$($Record.sha256)]"
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# FANUC Job Review Packet: $program")
$lines.Add("")
$lines.Add("## Gates")
$lines.Add("- Spec validation passed: $($manifest.gates.specValidationPassed)")
$lines.Add("- LS safety passed: $($manifest.gates.lsSafetyPassed)")
if ($manifest.gates.PSObject.Properties.Name -contains "motionGeneratedLsPassed") {
$lines.Add("- Motion LS matches spec: $($manifest.gates.motionGeneratedLsPassed)")
}
$lines.Add("- Round-trip overall match: $($manifest.gates.roundTripOverallMatch)")
$optionalEvidenceRecorded = (
    ($manifest.files.PSObject.Properties.Name -contains "simulation" -and [bool]$manifest.files.simulation.exists) -or
    ($manifest.files.PSObject.Properties.Name -contains "roboguideEvidencePacket" -and [bool]$manifest.files.roboguideEvidencePacket.exists)
)
$lines.Add("- Optional RoboGuide/manual evidence present: $optionalEvidenceRecorded")
$lines.Add("- Local evidence passed: $($manifest.gates.localEvidencePassed)")
$lines.Add("- Ready for upload: $($manifest.gates.readyForUpload)")
$lines.Add("")
if ($null -ne $motionSpec) {
    $lines.Add("## Motion Application")
    $lines.Add("- Template: $($motionSpec.generation.templateId)")
    $lines.Add("- UFRAME[$($motionSpec.resources.userFrame.number)]: $($motionSpec.resources.userFrame.name)")
    $lines.Add("- UTOOL[$($motionSpec.resources.userTool.number)]: $($motionSpec.resources.userTool.name)")
    $lines.Add("- PAYLOAD[$($motionSpec.resources.payload.number)]: $($motionSpec.resources.payload.name)")
    $lines.Add("")
    $lines.Add("## Motion Sequence")
    foreach ($step in @($motionSpec.motionPlan.motionSequence)) {
        $termination = if ($step.termination.type -eq "CNT") { "CNT$([int]$step.termination.value)" } else { "FINE" }
        $lines.Add("- $($step.stepName): $($step.motionType) PR[$([int]$step.target.number)] $($step.speed.value)$($step.speed.unit) $termination")
    }
    $lines.Add("")
    if ($null -ne $motionSpec.motionPlan.PSObject.Properties["positionArchitecture"]) {
        $architecture = $motionSpec.motionPlan.positionArchitecture
        $lines.Add("## Position Architecture")
        $lines.Add("- Strategy: $($architecture.strategy)")
        $lines.Add("- Calc program: $($architecture.calcProgram.programName) required=$($architecture.calcProgram.required) callBeforeMotion=$($architecture.calcProgram.callBeforeMotion) verified=$($architecture.calcProgram.verified)")
        $lines.Add("- Breadcrumb: R[$($architecture.breadcrumb.register)] $($architecture.breadcrumb.assignmentPosition), $($architecture.breadcrumb.semantics)")
        $lines.Add("- Inline offsets default allowed: $($architecture.inlineOffsetPolicy.defaultAllowed)")
        $lines.Add("")
        if (@($architecture.prFamilies).Count -gt 0) {
            $lines.Add("### PR Families")
            foreach ($family in @($architecture.prFamilies)) {
                $lines.Add("- $($family.familyName): PR[$([int]$family.start)]..PR[$([int]$family.start + [int]$family.size - 1)] owner=$($family.owner) verified=$($family.verified)")
            }
            $lines.Add("")
        }
        if (@($architecture.offsetPrs).Count -gt 0) {
            $lines.Add("### Offset PRs")
            foreach ($offsetPr in @($architecture.offsetPrs)) {
                $zeroing = if ($null -ne $offsetPr.PSObject.Properties["zeroingMethod"]) { $offsetPr.zeroingMethod } else { "not-declared" }
                $lines.Add("- PR[$([int]$offsetPr.number):$($offsetPr.name)] owner=$($offsetPr.owner) aiMayPopulate=$($offsetPr.aiMayPopulate) zeroing=$zeroing verified=$($offsetPr.verified)")
            }
            $lines.Add("")
        }
        if (@($architecture.derivedPrs).Count -gt 0) {
            $lines.Add("### Derived PRs")
            foreach ($derivedPr in @($architecture.derivedPrs)) {
                $lines.Add("- PR[$([int]$derivedPr.number):$($derivedPr.name)] role=$($derivedPr.role) = PR[$([int]$derivedPr.sourceBasePr)] + PR[$([int]$derivedPr.sourceOffsetPr)] writer=$($derivedPr.writer) MOVE_TO=$($derivedPr.availableForPendantMoveTo) verified=$($derivedPr.verified)")
            }
            $lines.Add("")
        }
        if (@($architecture.inlineOffsetPolicy.exceptions).Count -gt 0) {
            $lines.Add("### Inline Offset Exceptions")
            foreach ($exception in @($architecture.inlineOffsetPolicy.exceptions)) {
                $lines.Add("- $($exception.stepName): $($exception.modifier), reviewed=$($exception.reviewed), reason=$($exception.reason)")
            }
            $lines.Add("")
        }
    }
}
$lines.Add("## Review Status")
$lines.Add("- Human review: $($manifest.humanReview.status)")
$lines.Add("- Upload: $($manifest.upload.status)")
$lines.Add("")
$lines.Add("## Files To Inspect")
$lines.Add((Format-FileLine -Label "Spec" -Record $manifest.files.spec))
$lines.Add((Format-FileLine -Label "Generated LS" -Record $manifest.files.generatedSource))
$lines.Add((Format-FileLine -Label "Compiled TP" -Record $manifest.files.compiled))
$lines.Add((Format-FileLine -Label "Decoded LS" -Record $manifest.files.decoded))
$lines.Add((Format-FileLine -Label "Validation" -Record $manifest.files.validation))
$lines.Add((Format-FileLine -Label "Round-trip" -Record $manifest.files.roundTrip))
$lines.Add((Format-FileLine -Label "Simulation" -Record $manifest.files.simulation))
$lines.Add((Format-FileLine -Label "RoboGuide evidence packet" -Record $manifest.files.roboguideEvidencePacket))
$lines.Add((Format-FileLine -Label "RoboGuide evidence notes" -Record $manifest.files.roboguideEvidencePacketMarkdown))
$lines.Add("")
$lines.Add("## Review Notes")
$lines.Add("- Confirm program name and /PROG match the intended generated program.")
$lines.Add("- Confirm operations match the spec intent.")
if ($null -ne $motionSpec) {
    $lines.Add("- Confirm UFRAME, UTOOL, PAYLOAD, and each PR target match the reviewed application.")
    $lines.Add("- Confirm every motion line in the LS matches the motion sequence above.")
    if ($null -ne $motionSpec.motionPlan.PSObject.Properties["positionArchitecture"]) {
        $lines.Add("- Confirm calculated PRs are pendant-visible and match the reviewed PR family/offset contract.")
        $lines.Add("- Confirm breadcrumb semantics are diagnostic only and not treated as actual robot position after CNT moves.")
    }
} else {
    $lines.Add("- Confirm no motion or controller-side behavior appears unless explicitly reviewed.")
}
$lines.Add("- Confirm round-trip evidence matches expectations.")
$lines.Add("- Confirm whether optional RoboGuide/manual evidence is useful for the program risk.")
$lines.Add("- Operator-owned robot setup and physical verification are not tracked as separate tool gates.")

$lines -join "`r`n"
