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
    [string]$UploadLogPath,

    [ValidateSet("auto", "spec", "ls-derived-auto-home")]
    [string]$JobKind = "auto"
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
$commissioningPolicyPath = if ($config.CommissioningPolicyPath) {
    if ([System.IO.Path]::IsPathRooted($config.CommissioningPolicyPath)) {
        $config.CommissioningPolicyPath
    } elseif (Test-Path -LiteralPath (Join-Path $projectRoot $config.CommissioningPolicyPath)) {
        Join-Path $projectRoot $config.CommissioningPolicyPath
    } else {
        Join-Path $configRoot $config.CommissioningPolicyPath
    }
} else {
    Join-Path $projectRoot "config\commissioning-policy.psd1"
}
$commissioningPolicy = if (Test-Path -LiteralPath $commissioningPolicyPath) {
    Import-PowerShellDataFile -LiteralPath $commissioningPolicyPath
} else {
    $null
}
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
$autoHomeMapPath = Join-Path $resolvedOutputRoot "a-main-auto-home-map.json"
$autoHomeSummaryPath = Join-Path $resolvedOutputRoot "a-main-auto-home-map.md"
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

$resolvedJobKind = if ($JobKind -ne "auto") {
    $JobKind
} elseif ((Test-Path -LiteralPath $programSpecPath) -or (Test-Path -LiteralPath $motionSpecPath)) {
    "spec"
} elseif ($program -eq "A_AUTO_HOME" -and (Test-Path -LiteralPath $autoHomeMapPath)) {
    "ls-derived-auto-home"
} else {
    "spec"
}

function Test-AutoHomeContract {
    param(
        [string]$SourcePath,
        [string]$MapPath,
        [string]$ExpectedProgram
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $firstInstruction = $null
    $secondInstruction = $null
    $map = $null
    $cntRecords = @()

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        $findings.Add([ordered]@{
            severity = "error"
            code = "source-missing"
            message = "Generated source not found: $SourcePath"
        })
    } else {
        $text = Get-Content -LiteralPath $SourcePath -Raw
        $mnMatch = [regex]::Match($text, '(?is)/MN\s*(.*?)\s*/POS')
        if (-not $mnMatch.Success) {
            $findings.Add([ordered]@{
                severity = "error"
                code = "mn-section-missing"
                message = "Could not find /MN section in $SourcePath"
            })
        } else {
            $instructions = New-Object System.Collections.Generic.List[string]
            foreach ($line in ($mnMatch.Groups[1].Value -split '\r?\n')) {
                $normalized = $line.Trim()
                if ($normalized.Length -eq 0) {
                    continue
                }
                if ($normalized -match '^:\s*') {
                    continue
                }
                $normalized = [regex]::Replace($normalized, '^\d+\s*:\s*', '')
                if ($normalized.Trim().Length -eq 0) {
                    continue
                }
                $instructions.Add($normalized.Trim())
            }
            if ($instructions.Count -gt 0) {
                $firstInstruction = $instructions[0]
            }
            if ($instructions.Count -gt 1) {
                $secondInstruction = $instructions[1]
            }
        }
    }

    if ($firstInstruction -notmatch '^(?i)OVERRIDE\s*=\s*10%\s*;?$') {
        $findings.Add([ordered]@{
            severity = "error"
            code = "override-not-first"
            message = "First executable instruction must be OVERRIDE=10% before route selection or motion."
            actual = $firstInstruction
        })
    }

    if ($secondInstruction -notmatch '^(?i)WAIT\s+\.?10\s*\(\s*sec\s*\)\s*;?$') {
        $findings.Add([ordered]@{
            severity = "error"
            code = "override-boundary-missing"
            message = "Second executable instruction must be WAIT .10(sec) as the reviewed override boundary."
            actual = $secondInstruction
        })
    }

    if (-not (Test-Path -LiteralPath $MapPath)) {
        $findings.Add([ordered]@{
            severity = "error"
            code = "map-missing"
            message = "Auto-home route map not found: $MapPath"
        })
    } else {
        $map = Get-Content -LiteralPath $MapPath -Raw | ConvertFrom-Json
        if ($map.autoHomeProgramName -and $map.autoHomeProgramName.ToUpperInvariant() -ne $ExpectedProgram) {
            $findings.Add([ordered]@{
                severity = "error"
                code = "map-program-mismatch"
                message = "Auto-home map program name does not match manifest program."
                expected = $ExpectedProgram
                actual = $map.autoHomeProgramName
            })
        }

        $cntRecords = @($map.motionRecords | Where-Object { $_.MotionTail -match '(?i)\bCNT\d*\b' })
        if ($cntRecords.Count -gt 0) {
            $findings.Add([ordered]@{
                severity = "warning"
                code = "cnt-breadcrumb-source"
                message = "Breadcrumb source contains CNT motion. Current project policy accepts this as nonblocking because the cell owner uses constant path and owns robot-side route review before commissioning."
                count = $cntRecords.Count
                examples = @($cntRecords | Select-Object -First 10 ProgramName, SourceLineNumber, PositionRegister, MotionTail)
            })
        }
    }

    return [ordered]@{
        jobKind = "ls-derived-auto-home"
        passed = (@($findings.ToArray() | Where-Object { $_.severity -eq "error" }).Count -eq 0)
        sourcePath = $SourcePath
        mapPath = $MapPath
        firstInstruction = $firstInstruction
        secondInstruction = $secondInstruction
        breadcrumbRegister = if ($null -ne $map) { $map.breadcrumbRegister } else { $null }
        motionStatementCount = if ($null -ne $map) { $map.motionStatementCount } else { $null }
        cntBreadcrumbMotionCount = $cntRecords.Count
        findings = @($findings.ToArray())
    }
}

$validations = [ordered]@{
    timestamp = (Get-Date).ToString("o")
    programName = $program
    jobKind = $resolvedJobKind
    spec = if ($resolvedJobKind -eq "ls-derived-auto-home") {
        $autoHomeContract = Test-AutoHomeContract -SourcePath $sourcePath -MapPath $autoHomeMapPath -ExpectedProgram $program
        [ordered]@{
            name = "LsDerivedAutoHomeContract"
            passed = [bool]$autoHomeContract.passed
            result = $autoHomeContract
            error = if ([bool]$autoHomeContract.passed) { $null } else { "Auto-home contract failed; see result.findings." }
        }
    } elseif (Test-Path -LiteralPath $specPath) {
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
$uploadGate = if ($null -ne $commissioningPolicy -and $commissioningPolicy.UploadGate) {
    $commissioningPolicy.UploadGate
} else {
    "human-review"
}
$standingUploadApproval = ($uploadGate -eq "local-evidence")
$readyForUpload = ($localEvidencePassed -and ($humanReview.status -eq "approved" -or $standingUploadApproval))
$autoHomeCntBreadcrumbMotionCount = if ($resolvedJobKind -eq "ls-derived-auto-home" -and $null -ne $validations.spec.result) {
    [int]$validations.spec.result.cntBreadcrumbMotionCount
} else {
    $null
}
$readyForUploadReason = if (-not $localEvidencePassed) {
    "blocked: local evidence has not passed"
} elseif ($humanReview.status -eq "approved") {
    "ready: per-job human review approved"
} elseif ($standingUploadApproval) {
    "ready: standing commissioning policy allows upload after local evidence; operator owns execution"
} else {
    "blocked: human review approval required"
}

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
        commissioningPolicy = Get-FileRecord $commissioningPolicyPath
        uploadReadbackTp = Get-FileRecord $uploadReadbackTpPath
        uploadReadbackLs = Get-FileRecord $uploadReadbackLsPath
        uploadReadback = Get-FileRecord $uploadReadbackPath
        autoHomeMap = Get-FileRecord $autoHomeMapPath
        autoHomeSummary = Get-FileRecord $autoHomeSummaryPath
        simulation = Get-FileRecord $simulationPath
        reviewPacket = Get-FileRecord $reviewPacketPath
        roboguideTestPlan = Get-FileRecord $roboguideTestPlanPath
        roboguideEvidencePacket = Get-FileRecord $roboguideEvidencePacketPath
        roboguideEvidencePacketMarkdown = Get-FileRecord $roboguideEvidencePacketMarkdownPath
    }
    gates = [ordered]@{
        specValidationPassed = [bool]$validations.spec.passed
        jobKind = $resolvedJobKind
        lsSafetyPassed = [bool]$validations.lsSafety.passed
        motionGeneratedLsPassed = $motionGeneratedLsPassed
        autoHomeContractPassed = if ($resolvedJobKind -eq "ls-derived-auto-home") { [bool]$validations.spec.passed } else { $null }
        autoHomeCntBreadcrumbMotionCount = $autoHomeCntBreadcrumbMotionCount
        roundTripInstructionMatch = if ($null -ne $roundTrip) { [bool]$roundTrip.instructionMatch } else { $false }
        roundTripOverallMatch = $roundTripPassed
        simulationRequired = $simulationRequired
        simulationPassed = $simulationPassed
        localEvidencePassed = $localEvidencePassed
        readyForUpload = $readyForUpload
        readyForUploadReason = $readyForUploadReason
    }
    upload = $upload
    humanReview = $humanReview
    commissioningPolicy = [ordered]@{
        path = $commissioningPolicyPath
        exists = (Test-Path -LiteralPath $commissioningPolicyPath)
        policyName = if ($null -ne $commissioningPolicy) { $commissioningPolicy.PolicyName } else { $null }
        uploadGate = $uploadGate
        automaticOperationApprovedByUpload = if ($null -ne $commissioningPolicy -and $null -ne $commissioningPolicy.OperatorExecutionBoundary) { [bool]$commissioningPolicy.OperatorExecutionBoundary.AutomaticOperationApprovedByUpload } else { $false }
        operatorRunAuthority = if ($null -ne $commissioningPolicy -and $null -ne $commissioningPolicy.OperatorExecutionBoundary) { $commissioningPolicy.OperatorExecutionBoundary.ProgramRunAuthority } else { "operator-only" }
    }
}

$manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding ASCII

[pscustomobject]@{
    ProgramName = $program
    LocalEvidencePassed = $manifest.gates.localEvidencePassed
    ReadyForUpload = $manifest.gates.readyForUpload
    ManifestPath = (Get-Item -LiteralPath $manifestPath).FullName
    ValidationPath = (Get-Item -LiteralPath $validationPath).FullName
}
