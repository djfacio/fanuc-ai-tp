[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,31}$')]
    [string]$ProgramName,

    [string]$OutputRoot = "generated",
    [string]$ConfigPath = "..\config\robot.psd1",

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
if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $resolvedOutputRoot = $OutputRoot
} else {
    $resolvedOutputRoot = Join-Path $projectRoot $OutputRoot
}
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
$program = $ProgramName.ToUpperInvariant()
$jobDir = Join-Path (Join-Path $resolvedOutputRoot "jobs") $program
$manifestPath = Join-Path $jobDir "manifest.json"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Manifest not found: $manifestPath. Run Update-FanucJobManifest.ps1 first."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json

function ConvertTo-OrderedSection {
    param(
        [object]$Section,
        [hashtable]$Defaults
    )

    $ordered = [ordered]@{}
    foreach ($key in $Defaults.Keys) {
        $value = $Defaults[$key]
        if ($null -ne $Section -and $Section.PSObject.Properties.Name -contains $key) {
            $value = $Section.$key
        }
        $ordered[$key] = $value
    }
    return $ordered
}

$uploadLog = if ($UploadLogPath) {
    if ([System.IO.Path]::IsPathRooted($UploadLogPath)) {
        $UploadLogPath
    } else {
        Join-Path $projectRoot $UploadLogPath
    }
} else {
    $null
}

$upload = ConvertTo-OrderedSection -Section $manifest.upload -Defaults @{
    status = "not-recorded"
    logPath = $null
    uploadedAt = $null
}

$humanReview = ConvertTo-OrderedSection -Section $manifest.humanReview -Defaults @{
    status = "not-recorded"
    reviewer = $null
    reviewedAt = $null
    notes = $null
}

if ($UploadStatus) {
    $upload.status = $UploadStatus
    if ($UploadStatus -eq "uploaded") {
        $upload.uploadedAt = (Get-Date).ToString("o")
    } elseif ($UploadStatus -eq "not-recorded") {
        $upload.uploadedAt = $null
    }
}
if ($uploadLog) {
    $upload.logPath = $uploadLog
}

if ($HumanReviewStatus) {
    $humanReview.status = $HumanReviewStatus
    if ($HumanReviewStatus -eq "not-recorded") {
        $humanReview.reviewedAt = $null
    } else {
        $humanReview.reviewedAt = (Get-Date).ToString("o")
    }
}
if ($Reviewer) {
    $humanReview.reviewer = $Reviewer
}
if ($HumanReviewNotes) {
    $humanReview.notes = $HumanReviewNotes
}

$manifest.upload = [pscustomobject]$upload
$manifest.humanReview = [pscustomobject]$humanReview

$localEvidencePassed = if ($null -ne $manifest.gates -and $manifest.gates.PSObject.Properties.Name -contains "localEvidencePassed") {
    [bool]$manifest.gates.localEvidencePassed
} else {
    $false
}

$uploadGate = if ($null -ne $manifest.commissioningPolicy -and $manifest.commissioningPolicy.uploadGate) {
    $manifest.commissioningPolicy.uploadGate
} elseif ($null -ne $commissioningPolicy -and $commissioningPolicy.UploadGate) {
    $commissioningPolicy.UploadGate
} else {
    "human-review"
}
$standingUploadApproval = ($uploadGate -eq "local-evidence")
$manifest.gates.readyForUpload = ($localEvidencePassed -and ($manifest.humanReview.status -eq "approved" -or $standingUploadApproval))
$manifest.gates.readyForUploadReason = if (-not $localEvidencePassed) {
    "blocked: local evidence has not passed"
} elseif ($manifest.humanReview.status -eq "approved") {
    "ready: per-job human review approved"
} elseif ($standingUploadApproval) {
    "ready: standing commissioning policy allows upload after local evidence; operator owns execution"
} else {
    "blocked: human review approval required"
}
$manifest.updatedAt = (Get-Date).ToString("o")

if ($PSCmdlet.ShouldProcess($manifestPath, "Update FANUC job status")) {
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding ASCII
}

[pscustomobject]@{
    ProgramName = $program
    LocalEvidencePassed = $localEvidencePassed
    ReadyForUpload = [bool]$manifest.gates.readyForUpload
    UploadGate = $uploadGate
    HumanReviewStatus = $manifest.humanReview.status
    UploadStatus = $manifest.upload.status
    ManifestPath = (Get-Item -LiteralPath $manifestPath).FullName
}
