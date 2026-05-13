param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$ProjectPath,
    [string]$ConfigPath = "..\config\robot.psd1",
    [string]$CellMapPath = "..\config\cell-map.psd1",
    [string]$OutputRoot = "generated",
    [switch]$SkipOptionalEvidence,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

if ($ProjectPath) {
    $resolvedProjectPath = Resolve-Path -LiteralPath $ProjectPath
    $projectPackPath = Join-Path $resolvedProjectPath "project.psd1"
    if (-not (Test-Path -LiteralPath $projectPackPath)) {
        throw "Project pack manifest not found: $projectPackPath"
    }

    $projectPack = Import-PowerShellDataFile -LiteralPath $projectPackPath
    if (-not [System.IO.Path]::IsPathRooted($ConfigPath) -and $ConfigPath -eq "..\config\robot.psd1") {
        $ConfigPath = Join-Path $resolvedProjectPath $projectPack.Config.Robot
    }
    if (-not [System.IO.Path]::IsPathRooted($CellMapPath) -and $CellMapPath -eq "..\config\cell-map.psd1") {
        $CellMapPath = Join-Path $resolvedProjectPath $projectPack.Config.CellMap
    }
    if (-not [System.IO.Path]::IsPathRooted($OutputRoot) -and $OutputRoot -eq "generated") {
        $OutputRoot = Join-Path $resolvedProjectPath $projectPack.OutputRoot
    }
    if (-not [System.IO.Path]::IsPathRooted($SpecPath)) {
        $SpecPath = Join-Path $resolvedProjectPath $SpecPath
    }
}

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

$validation = & $motionSpecValidator -SpecPath $resolvedSpec -CellMapPath $CellMapPath
if (-not $validation.ReadyForGeneration) {
    $messages = $validation.GenerationGateMessages | ForEach-Object { "- $_" }
    throw "Motion application spec is not ready for generation:`n$($messages -join "`n")"
}

$generated = & $motionGenerator -SpecPath $resolvedSpec -ConfigPath $resolvedConfig -CellMapPath $CellMapPath -OutputRoot $OutputRoot -Force:$Force
& $motionLsValidator -SpecPath $generated.JobSpecPath -LsPath $generated.SourcePath -CellMapPath $CellMapPath -Quiet
& $roundTripTool -LsPath $generated.SourcePath -ConfigPath $resolvedConfig -OutputRoot $OutputRoot -Force:$Force | Out-Null

if (-not $SkipOptionalEvidence) {
    $evidencePacketPath = Join-Path $generated.JobDirectory "roboguide-evidence-packet.json"
    & $evidencePacketTool -SpecPath $generated.JobSpecPath -CellMapPath $CellMapPath -OutputPath $evidencePacketPath -WriteMarkdown -Force | Out-Null
}

$manifest = & $manifestTool -ProgramName $programName -ConfigPath $resolvedConfig -OutputRoot $OutputRoot

$reviewPacket = & $reviewPacketTool -ProgramName $programName -OutputRoot $OutputRoot
$reviewPacketPath = Join-Path $generated.JobDirectory "review-packet.md"
$reviewPacket | Set-Content -LiteralPath $reviewPacketPath -Encoding ASCII
$manifest = & $manifestTool -ProgramName $programName -ConfigPath $resolvedConfig -OutputRoot $OutputRoot

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
