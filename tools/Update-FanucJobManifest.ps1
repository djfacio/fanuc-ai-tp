param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,31}$')]
    [string]$ProgramName,

    [string]$ConfigPath = "..\config\robot.psd1",
    [string]$OutputRoot = "generated",

    [ValidateSet("not-recorded", "approved", "rejected", "needs-changes")]
    [string]$HumanReviewStatus,
    [string]$Reviewer,
    [string]$HumanReviewNotes,

    [ValidateSet("not-recorded", "uploaded", "failed")]
    [string]$UploadStatus,
    [string]$UploadLogPath
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig
$configRoot = Split-Path -Parent $resolvedConfig
$cellMapPath = if ($config.CellMapPath) {
    if ([System.IO.Path]::IsPathRooted($config.CellMapPath)) {
        $config.CellMapPath
    } elseif (Test-Path -LiteralPath (Join-Path $projectRoot $config.CellMapPath)) {
        Join-Path $projectRoot $config.CellMapPath
    } else {
        Join-Path $configRoot $config.CellMapPath
    }
} else {
    Join-Path $projectRoot "config\cell-map.psd1"
}
if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $resolvedOutputRoot = $OutputRoot
} else {
    $resolvedOutputRoot = Join-Path $projectRoot $OutputRoot
}
$program = $ProgramName.ToUpperInvariant()
$jobDir = Join-Path (Join-Path $resolvedOutputRoot "jobs") $program
$sourcePath = Join-Path (Join-Path $resolvedOutputRoot "sources") ($program + ".LS")
$jobSourcePath = Join-Path $jobDir ($program + ".LS")
$compiledPath = Join-Path (Join-Path $resolvedOutputRoot "compiled") ($program + ".TP")
$jobCompiledPath = Join-Path $jobDir ($program + ".TP")
$programSpecPath = Join-Path $jobDir "spec.json"
$motionSpecPath = Join-Path $jobDir "motion-application-spec.json"
$specPath = if (Test-Path -LiteralPath $programSpecPath) { $programSpecPath } else { $motionSpecPath }
$decodedPath = Join-Path $jobDir "decoded.LS"
$roundTripPath = Join-Path $jobDir "roundtrip.json"
$uploadReadbackDir = Join-Path $jobDir "upload-readback"
$uploadReadbackTpPath = Join-Path $uploadReadbackDir ($program + ".TP")
$uploadReadbackLsPath = Join-Path $uploadReadbackDir ($program + ".LS")
$uploadReadbackPath = Join-Path $jobDir "upload-readback.json"
$simulationPath = Join-Path $jobDir "simulation.json"
$reviewPacketPath = Join-Path $jobDir "review-packet.md"
$roboguideTestPlanPath = Join-Path $jobDir "roboguide-test-plan.md"
$roboguideEvidencePacketPath = Join-Path $jobDir "roboguide-evidence-packet.json"
$roboguideEvidencePacketMarkdownPath = Join-Path $jobDir "roboguide-evidence-packet.md"
$validationPath = Join-Path $jobDir "validation.json"
$manifestPath = Join-Path $jobDir "manifest.json"

$previousManifest = if (Test-Path -LiteralPath $manifestPath) {
    Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
} else {
    $null
}

if (-not (Test-Path -LiteralPath $jobDir)) {
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
}

if ((Test-Path -LiteralPath $compiledPath) -and -not (Test-Path -LiteralPath $jobCompiledPath)) {
    Copy-Item -LiteralPath $compiledPath -Destination $jobCompiledPath -Force
}

function Get-FileRecord {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{
            path = $Path
            exists = $false
        }
    }

    $item = Get-Item -LiteralPath $Path
    return [ordered]@{
        path = $item.FullName
        exists = $true
        length = $item.Length
        lastWriteTimeUtc = $item.LastWriteTimeUtc.ToString("o")
        sha256 = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash
    }
}

function Invoke-Validator {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    try {
        $result = & $Command
        return [ordered]@{
            name = $Name
            passed = $true
            result = $result
            error = $null
        }
    } catch {
        return [ordered]@{
            name = $Name
            passed = $false
            result = $null
            error = $_.Exception.Message
        }
    }
}

$specValidator = Join-Path $scriptRoot "Test-FanucProgramSpec.ps1"
$motionSpecValidator = Join-Path $scriptRoot "Test-FanucMotionApplicationSpec.ps1"
$motionGeneratedLsValidator = Join-Path $scriptRoot "Test-FanucMotionGeneratedLs.ps1"
$lsValidator = Join-Path $scriptRoot "Test-FanucLsSafety.ps1"
$specValidationName = if (Test-Path -LiteralPath $programSpecPath) { "ProgramSpec" } else { "MotionApplicationSpec" }
$isMotionApplicationJob = (-not (Test-Path -LiteralPath $programSpecPath) -and (Test-Path -LiteralPath $motionSpecPath))

$validations = [ordered]@{
    timestamp = (Get-Date).ToString("o")
    programName = $program
    spec = if (Test-Path -LiteralPath $specPath) {
        Invoke-Validator -Name $specValidationName -Command {
            if (Test-Path -LiteralPath $programSpecPath) {
                & $specValidator -SpecPath $specPath -ConfigPath $resolvedConfig
            } else {
                & $motionSpecValidator -SpecPath $specPath -CellMapPath $cellMapPath
            }
        }
    } else {
        [ordered]@{
            name = $specValidationName
            passed = $false
            result = $null
            error = "Spec not found: $programSpecPath or $motionSpecPath"
        }
    }
    lsSafety = if (Test-Path -LiteralPath $sourcePath) {
        Invoke-Validator -Name "LsSafety" -Command {
            & $lsValidator -LsPath $sourcePath -ProgramName $program -ConfigPath $resolvedConfig
        }
    } else {
        [ordered]@{
            name = "LsSafety"
            passed = $false
            result = $null
            error = "LS source not found: $sourcePath"
        }
    }
    motionGeneratedLs = if ($isMotionApplicationJob -and (Test-Path -LiteralPath $sourcePath)) {
        Invoke-Validator -Name "MotionGeneratedLs" -Command {
            & $motionGeneratedLsValidator -SpecPath $motionSpecPath -LsPath $sourcePath -CellMapPath $cellMapPath
        }
    } elseif ($isMotionApplicationJob) {
        [ordered]@{
            name = "MotionGeneratedLs"
            passed = $false
            result = $null
            error = "Motion generated LS not found: $sourcePath"
        }
    } else {
        [ordered]@{
            name = "MotionGeneratedLs"
            passed = $true
            result = $null
            error = "not applicable"
        }
    }
}

$validations | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $validationPath -Encoding ASCII

$roundTrip = if (Test-Path -LiteralPath $roundTripPath) {
    Get-Content -LiteralPath $roundTripPath -Raw | ConvertFrom-Json
} else {
    $null
}

$spec = if (Test-Path -LiteralPath $specPath) {
    Get-Content -LiteralPath $specPath -Raw | ConvertFrom-Json
} else {
    $null
}

$simulation = if (Test-Path -LiteralPath $simulationPath) {
    Get-Content -LiteralPath $simulationPath -Raw | ConvertFrom-Json
} else {
    $null
}

$previousUpload = if ($null -ne $previousManifest -and $null -ne $previousManifest.upload) {
    $previousManifest.upload
} else {
    [pscustomobject]@{
        status = "not-recorded"
        logPath = $null
        uploadedAt = $null
    }
}

$previousHumanReview = if ($null -ne $previousManifest -and $null -ne $previousManifest.humanReview) {
    $previousManifest.humanReview
} else {
    [pscustomobject]@{
        status = "not-recorded"
        reviewer = $null
        reviewedAt = $null
        notes = $null
    }
}

$upload = [ordered]@{
    status = if ($UploadStatus) { $UploadStatus } else { $previousUpload.status }
    logPath = if ($UploadLogPath) { $UploadLogPath } else { $previousUpload.logPath }
    uploadedAt = if ($UploadStatus -eq "uploaded") { (Get-Date).ToString("o") } else { $previousUpload.uploadedAt }
}

$humanReview = [ordered]@{
    status = if ($HumanReviewStatus) { $HumanReviewStatus } else { $previousHumanReview.status }
    reviewer = if ($Reviewer) { $Reviewer } else { $previousHumanReview.reviewer }
    reviewedAt = if ($HumanReviewStatus) { (Get-Date).ToString("o") } else { $previousHumanReview.reviewedAt }
    notes = if ($HumanReviewNotes) { $HumanReviewNotes } else { $previousHumanReview.notes }
}

$roundTripPassed = if ($null -ne $roundTrip -and $roundTrip.PSObject.Properties.Name -contains "overallMatch") {
    [bool]$roundTrip.overallMatch
} elseif ($null -ne $roundTrip) {
    [bool]$roundTrip.instructionMatch
} else {
    $false
}
$simulationRequired = (
    ($null -ne $spec -and $null -ne $spec.verification -and [bool]$spec.verification.roboguideRequired) -or
    ($null -ne $spec -and $null -ne $spec.evidence -and [bool]$spec.evidence.roboguideRequired)
)
$simulationPassed = ($null -ne $simulation -and $simulation.status -in @("not-required", "passed"))
$motionGeneratedLsPassed = [bool]$validations.motionGeneratedLs.passed
$localEvidencePassed = ([bool]$validations.spec.passed -and [bool]$validations.lsSafety.passed -and $motionGeneratedLsPassed -and $roundTripPassed)
$readyForUpload = ($localEvidencePassed -and $humanReview.status -eq "approved")

$manifest = [ordered]@{
    schemaVersion = 1
    updatedAt = (Get-Date).ToString("o")
    programName = $program
    controller = [ordered]@{
        robotIp = $config.RobotIp
        winOlpcVersion = $config.WinOlpcVersion
    }
    tools = [ordered]@{
        makeTpPath = $config.MakeTpPath
        makeTpExists = (Test-Path -LiteralPath $config.MakeTpPath)
        printTpPath = (Join-Path (Split-Path -Parent $config.MakeTpPath) "printtp.exe")
        robotIniPath = if ([System.IO.Path]::IsPathRooted($config.RobotIniPath)) { $config.RobotIniPath } elseif (Test-Path -LiteralPath (Join-Path $projectRoot $config.RobotIniPath)) { Join-Path $projectRoot $config.RobotIniPath } else { Join-Path $configRoot $config.RobotIniPath }
    }
    files = [ordered]@{
        spec = Get-FileRecord $specPath
        programSpec = Get-FileRecord $programSpecPath
        motionApplicationSpec = Get-FileRecord $motionSpecPath
        generatedSource = Get-FileRecord $sourcePath
        jobSource = Get-FileRecord $jobSourcePath
        compiled = Get-FileRecord $compiledPath
        jobCompiled = Get-FileRecord $jobCompiledPath
        decoded = Get-FileRecord $decodedPath
        validation = Get-FileRecord $validationPath
        roundTrip = Get-FileRecord $roundTripPath
        uploadReadbackTp = Get-FileRecord $uploadReadbackTpPath
        uploadReadbackLs = Get-FileRecord $uploadReadbackLsPath
        uploadReadback = Get-FileRecord $uploadReadbackPath
        simulation = Get-FileRecord $simulationPath
        reviewPacket = Get-FileRecord $reviewPacketPath
        roboguideTestPlan = Get-FileRecord $roboguideTestPlanPath
        roboguideEvidencePacket = Get-FileRecord $roboguideEvidencePacketPath
        roboguideEvidencePacketMarkdown = Get-FileRecord $roboguideEvidencePacketMarkdownPath
    }
    gates = [ordered]@{
        specValidationPassed = [bool]$validations.spec.passed
        lsSafetyPassed = [bool]$validations.lsSafety.passed
        motionGeneratedLsPassed = $motionGeneratedLsPassed
        roundTripInstructionMatch = if ($null -ne $roundTrip) { [bool]$roundTrip.instructionMatch } else { $false }
        roundTripOverallMatch = $roundTripPassed
        simulationRequired = $simulationRequired
        simulationPassed = $simulationPassed
        localEvidencePassed = $localEvidencePassed
        readyForUpload = $readyForUpload
    }
    upload = $upload
    humanReview = $humanReview
}

$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding ASCII

[pscustomobject]@{
    ProgramName = $program
    LocalEvidencePassed = $manifest.gates.localEvidencePassed
    ReadyForUpload = $manifest.gates.readyForUpload
    ManifestPath = (Get-Item -LiteralPath $manifestPath).FullName
    ValidationPath = (Get-Item -LiteralPath $validationPath).FullName
}
