param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$SchemaPath = "..\schemas\motion-application-spec.schema.json",
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
$schemaValidator = Join-Path $scriptRoot "Test-FanucJsonSchema.ps1"

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

if (-not $spec.evidence.roboguideRequired) {
    Add-Finding -Rule "RoboGuideRequired" -Message "Motion application specs must require RoboGuide evidence."
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

$readyForGeneration = ($readyGateFindings.Count -eq 0)
if ($spec.generation.allowed -and -not $readyForGeneration) {
    foreach ($message in $readyGateFindings.ToArray()) {
        Add-Finding -Rule "GenerationGate" -Message $message
    }
}
if ($spec.phase -in @("generation-ready", "generated", "uploaded", "t1-verified", "released") -and -not $readyForGeneration) {
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
