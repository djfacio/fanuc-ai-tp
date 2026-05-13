[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,31}$')]
    [string]$ProgramName,

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
$program = $ProgramName.ToUpperInvariant()
$jobDir = Join-Path (Join-Path $projectRoot "generated\jobs") $program
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

$manifest.gates.readyForUpload = ($localEvidencePassed -and $manifest.humanReview.status -eq "approved")
$manifest.updatedAt = (Get-Date).ToString("o")

if ($PSCmdlet.ShouldProcess($manifestPath, "Update FANUC job status")) {
    $manifest | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $manifestPath -Encoding ASCII
}

[pscustomobject]@{
    ProgramName = $program
    LocalEvidencePassed = $localEvidencePassed
    ReadyForUpload = [bool]$manifest.gates.readyForUpload
    HumanReviewStatus = $manifest.humanReview.status
    UploadStatus = $manifest.upload.status
    ManifestPath = (Get-Item -LiteralPath $manifestPath).FullName
}
