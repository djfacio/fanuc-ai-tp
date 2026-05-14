param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$OutputPath,
    [switch]$WriteMarkdown,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

function Resolve-InputPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return (Resolve-Path -LiteralPath (Join-Path $projectRoot $Path)).Path
}

function Resolve-OutputPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }
    return Join-Path $projectRoot $Path
}

$resolvedSpecPath = Resolve-InputPath $SpecPath
$validator = Join-Path $scriptRoot "Test-FanucWorkflowMigrationSpec.ps1"
$validation = & $validator -SpecPath $resolvedSpecPath
$spec = Get-Content -LiteralPath $resolvedSpecPath -Raw | ConvertFrom-Json

$program = $spec.generated.entryProgram.ToUpperInvariant()
if (-not $OutputPath) {
    $OutputPath = "generated\review-packets\$program-workflow-review.md"
}
$resolvedOutputPath = Resolve-OutputPath $OutputPath

if ((Test-Path -LiteralPath $resolvedOutputPath) -and -not $Force -and $WriteMarkdown) {
    throw "Workflow review packet already exists: $resolvedOutputPath. Use -Force to overwrite."
}

$blockingQuestions = @($spec.reviewQuestions | Where-Object { [bool]$_.blocking })
$importantQuestions = @($spec.reviewQuestions | Where-Object { -not [bool]$_.blocking })
$legacyCalls = @($spec.steps | ForEach-Object { @($_.legacyCalls) } | Where-Object { $_ } | Sort-Object -Unique)
$waits = @($spec.steps | ForEach-Object {
    $step = $_
    @($step.externalWaits) | ForEach-Object {
        [pscustomobject]@{
            step = $step.name
            signal = $_.signal
            expected = $_.expected
            timeoutSeconds = [double]$_.timeoutSeconds
            onTimeout = $_.onTimeout
        }
    }
})
$unboundedWaits = @($waits | Where-Object { $_.timeoutSeconds -le 0 })

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# Workflow Review Packet: $program")
$lines.Add("")
$lines.Add("## Bottom Line")
$lines.Add("- Baseline: $($spec.baseline.rootProgram)")
$lines.Add("- Target: $($spec.generated.entryProgram)")
$lines.Add("- Migration mode: $($spec.generated.migrationMode)")
$lines.Add("- Valid contract: $($validation.IsValid)")
$lines.Add("- Ready for LS generation: $($validation.ReadyForGeneration)")
$lines.Add("- Recommendation: do not generate LS yet; answer the blocking decisions below first.")
$lines.Add("")
$lines.Add("## What This First Slice Does")
$lines.Add("- Keeps the proven `F_` baseline untouched.")
$lines.Add("- Defines `A_MAIN` as a defensive wrapper-first migration target.")
$lines.Add("- Preserves current process order while requiring state, status, wait, and async-task contracts.")
$lines.Add("- Allows temporary `F_` calls during migration, but only as reviewed dependencies.")
$lines.Add("")
$lines.Add("## Proposed Robot Resources")
$lines.Add("- State register: $($spec.stateModel.stateRegister)")
$lines.Add("- Step status register: $($spec.stateModel.statusRegister)")
$lines.Add("- Global external wait timeout: $($spec.waitPolicy.globalTimeoutSeconds) seconds")
$lines.Add("- Wait timeout variable: ``$($spec.waitPolicy.controllerVariable)``")
$lines.Add("- Timeout variable write policy: $($spec.waitPolicy.variableWritePolicy)")
$lines.Add("- Production overwrite: $($spec.policy.productionOverwriteAllowed)")
$lines.Add("- Legacy `F_` calls during migration: $($spec.policy.allowLegacyFCallsDuringMigration)")
$lines.Add("- `RUN` during migration: $($spec.policy.allowRunDuringMigration)")
$lines.Add("")
$lines.Add("## Lifecycle State Model")
foreach ($state in @($spec.stateModel.states | Sort-Object code)) {
    $lines.Add("- $($state.code) = $($state.name): $($state.description)")
}
$lines.Add("")
$lines.Add("## WIP Representation")
$lines.Add("- Model: $($spec.stateModel.wipRepresentation.kind)")
$lines.Add("- $($spec.stateModel.wipRepresentation.description)")
foreach ($signal in @($spec.stateModel.wipRepresentation.signals)) {
    $lines.Add("- $($signal.signal): $($signal.meaning)")
}
$lines.Add("")
$lines.Add("## Lifecycle/WIP Examples")
if ($spec.stateModel.transitionExamples) {
    foreach ($example in @($spec.stateModel.transitionExamples)) {
        $lines.Add("- $($example.name): $($example.lifecycleState); $($example.wipCondition) $($example.description)")
    }
} else {
    $lines.Add("- none")
}
$lines.Add("")
$lines.Add("## Blocking Decisions")
if ($blockingQuestions.Count -eq 0) {
    $lines.Add("- none")
} else {
    foreach ($question in $blockingQuestions) {
        $lines.Add("- [$($question.id)] $($question.question)")
    }
}
$lines.Add("")
$lines.Add("## My Recommendations")
$lines.Add("- Keep `R[80]` as lifecycle mode only. Do not use it as the part-location truth in this pipelined cell.")
$lines.Add("- Keep existing WIP flags as the source of truth for station occupancy and staged parts.")
$lines.Add("- Use wrapper-first `A_MAIN` only where the called `F_` routine does not contain uncontrolled internal waits, or record an explicit exception.")
$lines.Add("- Do not allow `RUN F_FLEXI_LOADER` in generated `A_MAIN` until we define single-instance and stop behavior.")
$lines.Add("- Use the 180-second global external wait timeout and explicitly write the timeout variable immediately before each bounded wait.")
$lines.Add("- Preserve WIP state on any timeout; stop infeed; raise a specific alarm/status code; do not auto-clear part-location flags.")
$lines.Add("")
$lines.Add("## External Waits")
if ($waits.Count -eq 0) {
    $lines.Add("- none")
} else {
    foreach ($wait in $waits) {
        $lines.Add("- $($wait.step): wait for $($wait.signal) = $($wait.expected); timeout $($wait.timeoutSeconds) seconds; on timeout: $($wait.onTimeout)")
    }
}
$lines.Add("")
$lines.Add("## Temporary Legacy Calls Proposed")
if ($legacyCalls.Count -eq 0) {
    $lines.Add("- none")
} else {
    foreach ($call in $legacyCalls) {
        $lines.Add("- $call")
    }
}
$lines.Add("")
$lines.Add("## Important Nonblocking Questions")
if ($importantQuestions.Count -eq 0) {
    $lines.Add("- none")
} else {
    foreach ($question in $importantQuestions) {
        $lines.Add("- [$($question.id)] $($question.question)")
    }
}
$lines.Add("")
$lines.Add("## Audit Files")
$lines.Add("- Contract: $resolvedSpecPath")
$lines.Add("- Schema: schemas/workflow-migration-spec.schema.json")
$lines.Add("- Validator: tools/Test-FanucWorkflowMigrationSpec.ps1")
$lines.Add("")
$lines.Add("## Next Action")
$lines.Add("Answer the blocking decisions in plain language. I will update the contract and only generate `A_MAIN.LS` after the validator reports generation-ready.")

$markdown = $lines -join "`r`n"

if ($WriteMarkdown) {
    $parent = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }
    Set-Content -LiteralPath $resolvedOutputPath -Value $markdown -Encoding UTF8
}

[pscustomobject]@{
    ProgramName = $program
    IsValid = $validation.IsValid
    ReadyForGeneration = $validation.ReadyForGeneration
    BlockingDecisionCount = $blockingQuestions.Count
    UnboundedWaitCount = $unboundedWaits.Count
    OutputPath = if ($WriteMarkdown) { $resolvedOutputPath } else { $null }
    Markdown = if ($WriteMarkdown) { $null } else { $markdown }
}
