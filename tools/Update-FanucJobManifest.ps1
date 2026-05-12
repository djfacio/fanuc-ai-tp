param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,31}$')]
    [string]$ProgramName,

    [string]$ConfigPath = "..\config\robot.psd1",

    [ValidateSet("not-recorded", "approved", "rejected", "needs-changes")]
    [string]$HumanReviewStatus,
    [string]$Reviewer,
    [string]$HumanReviewNotes,

    [ValidateSet("not-recorded", "uploaded", "failed")]
    [string]$UploadStatus,
    [string]$UploadLogPath,

    [ValidateSet("not-recorded", "passed", "failed")]
    [string]$PendantVerificationStatus,
    [string]$PendantVerificationNotes
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
$program = $ProgramName.ToUpperInvariant()
$jobDir = Join-Path (Join-Path $projectRoot "generated\jobs") $program
$sourcePath = Join-Path (Join-Path $projectRoot "generated\sources") ($program + ".LS")
$jobSourcePath = Join-Path $jobDir ($program + ".LS")
$compiledPath = Join-Path (Join-Path $projectRoot "generated\compiled") ($program + ".TP")
$jobCompiledPath = Join-Path $jobDir ($program + ".TP")
$specPath = Join-Path $jobDir "spec.json"
$decodedPath = Join-Path $jobDir "decoded.LS"
$roundTripPath = Join-Path $jobDir "roundtrip.json"
$uploadReadbackDir = Join-Path $jobDir "upload-readback"
$uploadReadbackTpPath = Join-Path $uploadReadbackDir ($program + ".TP")
$uploadReadbackLsPath = Join-Path $uploadReadbackDir ($program + ".LS")
$uploadReadbackPath = Join-Path $jobDir "upload-readback.json"
$simulationPath = Join-Path $jobDir "simulation.json"
$reviewPacketPath = Join-Path $jobDir "review-packet.md"
$roboguideTestPlanPath = Join-Path $jobDir "roboguide-test-plan.md"
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
$lsValidator = Join-Path $scriptRoot "Test-FanucLsSafety.ps1"

$validations = [ordered]@{
    timestamp = (Get-Date).ToString("o")
    programName = $program
    spec = if (Test-Path -LiteralPath $specPath) {
        Invoke-Validator -Name "ProgramSpec" -Command {
            & $specValidator -SpecPath $specPath -ConfigPath $resolvedConfig
        }
    } else {
        [ordered]@{
            name = "ProgramSpec"
            passed = $false
            result = $null
            error = "Spec not found: $specPath"
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

$previousPendantVerification = if ($null -ne $previousManifest -and $null -ne $previousManifest.pendantVerification) {
    $previousManifest.pendantVerification
} else {
    [pscustomobject]@{
        status = "not-recorded"
        verifiedAt = $null
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

$pendantVerification = [ordered]@{
    status = if ($PendantVerificationStatus) { $PendantVerificationStatus } else { $previousPendantVerification.status }
    verifiedAt = if ($PendantVerificationStatus) { (Get-Date).ToString("o") } else { $previousPendantVerification.verifiedAt }
    notes = if ($PendantVerificationNotes) { $PendantVerificationNotes } else { $previousPendantVerification.notes }
}

$roundTripPassed = if ($null -ne $roundTrip -and $roundTrip.PSObject.Properties.Name -contains "overallMatch") {
    [bool]$roundTrip.overallMatch
} elseif ($null -ne $roundTrip) {
    [bool]$roundTrip.instructionMatch
} else {
    $false
}
$simulationRequired = ($null -ne $spec -and $null -ne $spec.verification -and [bool]$spec.verification.roboguideRequired)
$simulationPassed = if ($simulationRequired) {
    ($null -ne $simulation -and $simulation.status -eq "passed")
} else {
    ($null -eq $simulation -or $simulation.status -in @("not-required", "passed"))
}
$localEvidencePassed = ([bool]$validations.spec.passed -and [bool]$validations.lsSafety.passed -and $roundTripPassed -and $simulationPassed)
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
        robotIniPath = if ([System.IO.Path]::IsPathRooted($config.RobotIniPath)) { $config.RobotIniPath } else { Join-Path $projectRoot $config.RobotIniPath }
    }
    files = [ordered]@{
        spec = Get-FileRecord $specPath
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
    }
    gates = [ordered]@{
        specValidationPassed = [bool]$validations.spec.passed
        lsSafetyPassed = [bool]$validations.lsSafety.passed
        roundTripInstructionMatch = if ($null -ne $roundTrip) { [bool]$roundTrip.instructionMatch } else { $false }
        roundTripOverallMatch = $roundTripPassed
        simulationRequired = $simulationRequired
        simulationPassed = $simulationPassed
        localEvidencePassed = $localEvidencePassed
        readyForUpload = $readyForUpload
    }
    upload = $upload
    humanReview = $humanReview
    pendantVerification = $pendantVerification
}

$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding ASCII

[pscustomobject]@{
    ProgramName = $program
    LocalEvidencePassed = $manifest.gates.localEvidencePassed
    ReadyForUpload = $manifest.gates.readyForUpload
    ManifestPath = (Get-Item -LiteralPath $manifestPath).FullName
    ValidationPath = (Get-Item -LiteralPath $validationPath).FullName
}
