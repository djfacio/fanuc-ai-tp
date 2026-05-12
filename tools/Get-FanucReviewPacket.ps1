param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,31}$')]
    [string]$ProgramName
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$program = $ProgramName.ToUpperInvariant()
$jobDir = Join-Path (Join-Path $projectRoot "generated\jobs") $program
$manifestPath = Join-Path $jobDir "manifest.json"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found: $manifestPath"
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

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
$lines.Add("- Round-trip overall match: $($manifest.gates.roundTripOverallMatch)")
$lines.Add("- Local evidence passed: $($manifest.gates.localEvidencePassed)")
$lines.Add("- Ready for upload: $($manifest.gates.readyForUpload)")
$lines.Add("")
$lines.Add("## Review Status")
$lines.Add("- Human review: $($manifest.humanReview.status)")
$lines.Add("- Upload: $($manifest.upload.status)")
$lines.Add("- Pendant verification: $($manifest.pendantVerification.status)")
$lines.Add("")
$lines.Add("## Files To Inspect")
$lines.Add((Format-FileLine -Label "Spec" -Record $manifest.files.spec))
$lines.Add((Format-FileLine -Label "Generated LS" -Record $manifest.files.generatedSource))
$lines.Add((Format-FileLine -Label "Compiled TP" -Record $manifest.files.compiled))
$lines.Add((Format-FileLine -Label "Decoded LS" -Record $manifest.files.decoded))
$lines.Add((Format-FileLine -Label "Validation" -Record $manifest.files.validation))
$lines.Add((Format-FileLine -Label "Round-trip" -Record $manifest.files.roundTrip))
$lines.Add((Format-FileLine -Label "Simulation" -Record $manifest.files.simulation))
$lines.Add("")
$lines.Add("## Suggested Review Checklist")
$lines.Add("- Confirm program name and /PROG match the intended AI_ program.")
$lines.Add("- Confirm operations match the spec intent.")
$lines.Add("- Confirm no motion or controller-side behavior appears unless explicitly reviewed.")
$lines.Add("- Confirm round-trip evidence matches expectations.")
$lines.Add("- Confirm RoboGuide/simulation evidence requirements are appropriate for the program risk.")
$lines.Add("- Only then record human review with Set-FanucJobStatus.ps1.")

$lines -join "`r`n"
