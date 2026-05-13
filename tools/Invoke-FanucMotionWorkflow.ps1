param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$ConfigPath = "..\config\robot.psd1",
    [switch]$SkipOptionalEvidence,
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
    return (Resolve-Path -LiteralPath (Join-Path $scriptRoot $Path)).Path
}

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

$resolvedSpec = Resolve-InputPath -Path $SpecPath
$spec = Get-Content -LiteralPath $resolvedSpec -Raw | ConvertFrom-Json
$programName = $spec.programName.ToUpperInvariant()

$motionSpecValidator = Join-Path $scriptRoot "Test-FanucMotionApplicationSpec.ps1"
$motionGenerator = Join-Path $scriptRoot "New-FanucMotionLsFromSpec.ps1"
$motionLsValidator = Join-Path $scriptRoot "Test-FanucMotionGeneratedLs.ps1"
$roundTripTool = Join-Path $scriptRoot "Invoke-FanucTpRoundTrip.ps1"
$evidencePacketTool = Join-Path $scriptRoot "New-FanucRoboguideEvidencePacket.ps1"
$manifestTool = Join-Path $scriptRoot "Update-FanucJobManifest.ps1"
$reviewPacketTool = Join-Path $scriptRoot "Get-FanucReviewPacket.ps1"

$validation = & $motionSpecValidator -SpecPath $resolvedSpec
if (-not $validation.ReadyForGeneration) {
    $messages = $validation.GenerationGateMessages | ForEach-Object { "- $_" }
    throw "Motion application spec is not ready for generation:`n$($messages -join "`n")"
}

$generated = & $motionGenerator -SpecPath $resolvedSpec -ConfigPath $resolvedConfig -Force:$Force
& $motionLsValidator -SpecPath $generated.JobSpecPath -LsPath $generated.SourcePath -Quiet
& $roundTripTool -LsPath $generated.SourcePath -ConfigPath $resolvedConfig -Force:$Force | Out-Null

if (-not $SkipOptionalEvidence) {
    & $evidencePacketTool -SpecPath $generated.JobSpecPath -WriteMarkdown -Force | Out-Null
}

$manifest = & $manifestTool -ProgramName $programName -ConfigPath $resolvedConfig

$reviewPacket = & $reviewPacketTool -ProgramName $programName
$reviewPacketPath = Join-Path $generated.JobDirectory "review-packet.md"
$reviewPacket | Set-Content -LiteralPath $reviewPacketPath -Encoding ASCII
$manifest = & $manifestTool -ProgramName $programName -ConfigPath $resolvedConfig

$manifestJson = Get-Content -LiteralPath $manifest.ManifestPath -Raw | ConvertFrom-Json
$compiled = [bool]$manifestJson.files.compiled.exists
$uploadReadback = $null
if ($manifestJson.files.PSObject.Properties.Name -contains "uploadReadback" -and [bool]$manifestJson.files.uploadReadback.exists) {
    $uploadReadback = Get-Content -LiteralPath $manifestJson.files.uploadReadback.path -Raw | ConvertFrom-Json
}

$states = [ordered]@{
    planned = $true
    generationReady = [bool]$validation.ReadyForGeneration
    generated = [bool]$manifestJson.files.generatedSource.exists
    compiled = $compiled
    roundTripPassed = [bool]$manifestJson.gates.roundTripOverallMatch
    reviewed = ($manifestJson.humanReview.status -eq "approved")
    uploaded = ($manifestJson.upload.status -eq "uploaded")
    readbackPassed = ($null -ne $uploadReadback -and [bool]$uploadReadback.hashMatch -and [bool]$uploadReadback.decodeSucceeded)
}

[pscustomobject]@{
    ProgramName = $programName
    TemplateId = $spec.generation.templateId
    SourcePath = $generated.SourcePath
    JobDirectory = $generated.JobDirectory
    ManifestPath = $manifest.ManifestPath
    ReviewPacketPath = (Get-Item -LiteralPath $reviewPacketPath).FullName
    States = [pscustomobject]$states
}
