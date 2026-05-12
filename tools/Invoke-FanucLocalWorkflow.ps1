param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$ConfigPath = "..\config\robot.psd1",
    [ValidateSet("not-run", "passed", "failed", "not-required")]
    [string]$SimulationStatus,
    [string]$SimulationNotes,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

$resolvedSpec = Resolve-Path -LiteralPath $SpecPath
$schemaPath = Join-Path $projectRoot "schemas\program-spec.schema.json"
$spec = Get-Content -LiteralPath $resolvedSpec -Raw | ConvertFrom-Json
$programName = $spec.programName.ToUpperInvariant()

$schemaValidator = Join-Path $scriptRoot "Test-FanucJsonSchema.ps1"
$specValidator = Join-Path $scriptRoot "Test-FanucProgramSpec.ps1"
$generator = Join-Path $scriptRoot "New-FanucLsFromSpec.ps1"
$lsValidator = Join-Path $scriptRoot "Test-FanucLsSafety.ps1"
$roundTripTool = Join-Path $scriptRoot "Invoke-FanucTpRoundTrip.ps1"
$simulationTool = Join-Path $scriptRoot "Set-FanucSimulationEvidence.ps1"
$manifestTool = Join-Path $scriptRoot "Update-FanucJobManifest.ps1"
$reviewPacketTool = Join-Path $scriptRoot "Get-FanucReviewPacket.ps1"

& $schemaValidator -JsonPath $resolvedSpec -SchemaPath $schemaPath -Quiet
& $specValidator -SpecPath $resolvedSpec -ConfigPath $resolvedConfig -Quiet

$generated = & $generator -SpecPath $resolvedSpec -ConfigPath $resolvedConfig -Force:$Force
& $lsValidator -LsPath $generated.SourcePath -ProgramName $programName -ConfigPath $resolvedConfig -Quiet
& $roundTripTool -LsPath $generated.SourcePath -ConfigPath $resolvedConfig -Force:$Force | Out-Null

$simRequired = ($null -ne $spec.verification -and [bool]$spec.verification.roboguideRequired)
$resolvedSimulationStatus = if ($SimulationStatus) {
    $SimulationStatus
} elseif ($simRequired) {
    "not-run"
} else {
    "not-required"
}

$notes = if ($SimulationNotes) {
    $SimulationNotes
} elseif ($simRequired) {
    "Simulation required by spec; not run by local workflow."
} else {
    "No-motion local workflow; simulation not required by spec."
}

& $simulationTool -ProgramName $programName -Status $resolvedSimulationStatus -MotionInvolved:$false -Notes $notes | Out-Null
$manifest = & $manifestTool -ProgramName $programName -ConfigPath $resolvedConfig

$reviewPacket = & $reviewPacketTool -ProgramName $programName
$reviewPacketPath = Join-Path $generated.JobDirectory "review-packet.md"
$reviewPacket | Set-Content -LiteralPath $reviewPacketPath -Encoding ASCII
$manifest = & $manifestTool -ProgramName $programName -ConfigPath $resolvedConfig

[pscustomobject]@{
    ProgramName = $programName
    SourcePath = $generated.SourcePath
    JobDirectory = $generated.JobDirectory
    ManifestPath = $manifest.ManifestPath
    ReviewPacketPath = (Get-Item -LiteralPath $reviewPacketPath).FullName
    LocalEvidencePassed = $manifest.LocalEvidencePassed
    ReadyForUpload = $manifest.ReadyForUpload
}
