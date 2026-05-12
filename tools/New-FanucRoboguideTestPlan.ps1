param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,31}$')]
    [string]$ProgramName,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$program = $ProgramName.ToUpperInvariant()
$jobDir = Join-Path (Join-Path $projectRoot "generated\jobs") $program
$specPath = Join-Path $jobDir "spec.json"
$manifestPath = Join-Path $jobDir "manifest.json"
$planPath = Join-Path $jobDir "roboguide-test-plan.md"

if (-not (Test-Path -LiteralPath $specPath)) {
    throw "Spec not found: $specPath"
}
if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}
if ((Test-Path -LiteralPath $planPath) -and -not $Force) {
    throw "RoboGuide test plan already exists: $planPath. Use -Force to overwrite."
}

$spec = Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

$operationLines = foreach ($operation in $spec.operations) {
    $bits = @($operation.type)
    foreach ($name in @("name", "text", "register", "value", "signal", "state", "seconds")) {
        if ($operation.PSObject.Properties.Name -contains $name -and $null -ne $operation.$name) {
            $bits += ("{0}={1}" -f $name, $operation.$name)
        }
    }
    "- " + ($bits -join "; ")
}

$content = @(
    "# RoboGuide Test Plan: $program",
    "",
    "Generated: $(Get-Date -Format o)",
    "",
    "## Intent",
    "",
    $spec.intent,
    "",
    "## Artifact Evidence",
    "",
    "- Manifest: $manifestPath",
    "- LS safety passed: $($manifest.gates.lsSafetyPassed)",
    "- Round-trip passed: $($manifest.gates.roundTripOverallMatch)",
    "- Local evidence passed: $($manifest.gates.localEvidencePassed)",
    "",
    "## Safety",
    "",
    "- Motion allowed: $($spec.safety.motionAllowed)",
    "- Human review required: $($spec.safety.requiresHumanReview)",
    "- Notes: $($spec.safety.notes)",
    "",
    "## Operations",
    "",
    $operationLines,
    "",
    "## Setup",
    "",
    "- Open the intended RoboGuide workcell.",
    "- Confirm controller version and robot model match the manifest assumptions.",
    "- Load or confirm `$program.TP` in the virtual controller.",
    "- Set mode and override appropriate to the risk of the program.",
    "- Confirm frames, tools, payload, fixture state, and IO assumptions.",
    "",
    "## Expected Observations",
    "",
    "- Program behavior matches the operation list.",
    "- No unexpected motion, IO, UOP, system variable, or background-task behavior occurs.",
    "- Any marker registers or messages match the spec.",
    "",
    "## Result",
    "",
    "- Status: pending",
    "- Reviewer:",
    "- Date:",
    "- Notes:"
)

$content | Set-Content -LiteralPath $planPath -Encoding ASCII

[pscustomobject]@{
    ProgramName = $program
    TestPlanPath = (Get-Item -LiteralPath $planPath).FullName
}
