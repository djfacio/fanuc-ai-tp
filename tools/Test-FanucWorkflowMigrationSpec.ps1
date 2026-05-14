param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$SchemaPath = "..\schemas\workflow-migration-spec.schema.json",
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
$readyGateFindings = New-Object System.Collections.Generic.List[string]

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

function Add-ReadyGate {
    param([string]$Message)
    $readyGateFindings.Add($Message)
}

try {
    & $schemaValidator -JsonPath $resolvedSpec -SchemaPath $resolvedSchema -Quiet
} catch {
    Add-Finding -Rule "JsonSchema" -Message $_.Exception.Message
}

$spec = Get-Content -LiteralPath $resolvedSpec -Raw | ConvertFrom-Json

if ($spec.generated.entryProgram -eq $spec.baseline.rootProgram) {
    Add-Finding -Rule "BaselineOverwrite" -Message "Generated entry program must not equal baseline root program."
}

if ($spec.policy.productionOverwriteAllowed) {
    Add-Finding -Rule "ProductionOverwriteBlocked" -Message "Workflow migration must not allow production overwrite."
}

if (-not $spec.policy.humanReviewRequired) {
    Add-Finding -Rule "HumanReviewRequired" -Message "Workflow migration must require human review."
}

if (-not $spec.policy.requiresExplicitStateModel) {
    Add-Finding -Rule "ExplicitStateModelRequired" -Message "Workflow migration must require an explicit state model."
}

if (-not $spec.policy.requiresBoundedExternalWaits) {
    Add-Finding -Rule "BoundedExternalWaitsRequired" -Message "Workflow migration must require bounded external waits."
}

if ([double]$spec.waitPolicy.globalTimeoutSeconds -le 0) {
    Add-Finding -Rule "GlobalTimeoutRequired" -Message "waitPolicy.globalTimeoutSeconds must be positive."
}

if (-not $spec.waitPolicy.controllerVariable -or $spec.waitPolicy.controllerVariable.Trim().Length -lt 1) {
    Add-Finding -Rule "WaitTimeoutVariableRequired" -Message "waitPolicy.controllerVariable must identify the controller timeout variable or reviewed mechanism."
}

if ([double]$spec.waitPolicy.controllerWriteValue -le 0) {
    Add-Finding -Rule "WaitTimeoutWriteValueRequired" -Message "waitPolicy.controllerWriteValue must be the reviewed controller-native value for the timeout."
}

if (-not $spec.waitPolicy.controllerStorageUnits -or $spec.waitPolicy.controllerStorageUnits.Trim().Length -lt 1) {
    Add-Finding -Rule "WaitTimeoutStorageUnitsRequired" -Message "waitPolicy.controllerStorageUnits must record the controller-native units for the timeout variable."
}

$stateNames = @{}
foreach ($state in @($spec.stateModel.states)) {
    $name = [string]$state.name
    if ($stateNames.ContainsKey($name)) {
        Add-Finding -Rule "DuplicateState" -Message "State '$name' appears more than once."
    }
    $stateNames[$name] = $true
}

if (-not $stateNames.ContainsKey("FAULTED")) {
    Add-Finding -Rule "FaultedStateRequired" -Message "State model must include FAULTED."
}

if ($spec.stateModel.wipRepresentation.kind -ne "pipeline-flags") {
    Add-Finding -Rule "PipelineWipModelRequired" -Message "Pipelined workflow migration must represent WIP separately from lifecycle state."
}

foreach ($step in @($spec.steps)) {
    if (@($step.preconditions).Count -lt 1) {
        Add-ReadyGate -Message "Step '$($step.name)' must define at least one precondition."
    }
    if (@($step.successCriteria).Count -lt 1) {
        Add-ReadyGate -Message "Step '$($step.name)' must define at least one success criterion."
    }
    if (-not $step.failureBehavior -or $step.failureBehavior.Trim().Length -lt 1) {
        Add-ReadyGate -Message "Step '$($step.name)' must define failure behavior."
    }
    foreach ($wait in @($step.externalWaits)) {
        if ($spec.policy.requiresBoundedExternalWaits -and [double]$wait.timeoutSeconds -le 0) {
            Add-ReadyGate -Message "Step '$($step.name)' wait '$($wait.signal)' must have a positive timeout or a recorded exception outside generation-ready specs."
        }
    }
    foreach ($call in @($step.legacyCalls)) {
        if (-not $spec.policy.allowLegacyFCallsDuringMigration) {
            Add-ReadyGate -Message "Step '$($step.name)' calls baseline routine '$call' but legacy F_ calls are not allowed."
        }
    }
}

foreach ($task in @($spec.asyncTasks)) {
    foreach ($propertyName in @("singleInstancePolicy", "statusPolicy", "stopPolicy")) {
        $value = [string]$task.$propertyName
        if ($value -match '(?i)\bblocking\b') {
            Add-ReadyGate -Message "Async task '$($task.program)' has unresolved $propertyName."
        }
    }
}

$blockingQuestions = @($spec.reviewQuestions | Where-Object { [bool]$_.blocking })
if ($blockingQuestions.Count -gt 0) {
    foreach ($question in $blockingQuestions) {
        Add-ReadyGate -Message "Blocking review question '$($question.id)' must be answered: $($question.question)"
    }
}

if ($spec.generation.allowed -and $spec.generation.target -ne "ls-source") {
    Add-Finding -Rule "GenerationTargetInvalid" -Message "If generation.allowed is true, generation.target must be ls-source."
}

$readyForGeneration = ($readyGateFindings.Count -eq 0)
if ($spec.generation.allowed -and -not $readyForGeneration) {
    foreach ($message in $readyGateFindings.ToArray()) {
        Add-Finding -Rule "GenerationGate" -Message $message
    }
}

if ($spec.phase -in @("generation-ready", "generated", "uploaded", "operator-tested", "released") -and -not $readyForGeneration) {
    foreach ($message in $readyGateFindings.ToArray()) {
        Add-Finding -Rule "PhaseGate" -Message $message
    }
}

$result = [pscustomobject]@{
    Path = (Get-Item -LiteralPath $resolvedSpec).FullName
    ApplicationName = $spec.applicationName
    BaselineRootProgram = $spec.baseline.rootProgram
    GeneratedEntryProgram = $spec.generated.entryProgram
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
    throw "Workflow migration spec validation failed for $($result.Path):`n$($messages -join "`n")"
}
