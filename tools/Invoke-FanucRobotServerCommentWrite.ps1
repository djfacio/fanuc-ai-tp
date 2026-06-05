param(
    [string]$PlanPath = "generated\metadata\robot-server-comment-write-plan.json",
    [string]$OutputPath = "generated\metadata\robot-server-comment-write-evidence.json",
    [string]$ApprovalPhrase = "",
    [switch]$Execute,
    [switch]$AcceptRobotServerWrite
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $projectRoot $Path
}

function Get-CurrentComment {
    param(
        [string]$HostAddress,
        [string]$Family,
        [int]$Index
    )

    $reader = Join-Path $scriptRoot "Get-FanucRobotServerMetadata.ps1"
    $snapshot = & $reader -HostAddress $HostAddress -Families @($Family) -StartIndex $Index -EndIndex $Index
    $item = @($snapshot.Items | Where-Object { ([string]$_.Family).ToUpperInvariant() -eq $Family.ToUpperInvariant() -and [int]$_.Index -eq $Index } | Select-Object -First 1)
    if (-not $item) {
        throw "Readback did not find $Family[$Index]."
    }
    return [string]$item.Comment
}

$resolvedPlanPath = Resolve-ProjectPath $PlanPath
if (-not (Test-Path -LiteralPath $resolvedPlanPath)) {
    throw "Robot Server comment write plan not found: $resolvedPlanPath"
}

$plan = Get-Content -LiteralPath $resolvedPlanPath -Raw | ConvertFrom-Json
if (-not [bool]$plan.executionGate.commentsOnly) {
    throw "Plan does not declare commentsOnly=true."
}

$writes = @($plan.writes)
$evidenceRows = New-Object System.Collections.Generic.List[object]
$executed = [bool]$Execute

$phraseAccepted = (-not [bool]$plan.operatorApproval.required -or $ApprovalPhrase -eq [string]$plan.operatorApproval.requiredPhrase)

$evidence = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    executed = $executed
    acceptedRobotServerWrite = [bool]$AcceptRobotServerWrite
    hostAddress = [string]$plan.hostAddress
    planPath = (Get-Item -LiteralPath $resolvedPlanPath).FullName
    writeCount = $writes.Count
    operatorApproval = [ordered]@{
        required = [bool]$plan.operatorApproval.required
        requiredPhrase = [string]$plan.operatorApproval.requiredPhrase
        suppliedPhrase = $ApprovalPhrase
        phraseAccepted = $phraseAccepted
        warning = [string]$plan.operatorApproval.warning
    }
    rows = @()
}

if ($Execute) {
    if (-not [bool]$plan.approvedForLive) {
        throw "Robot Server comment write plan is not approved for live execution. Regenerate with New-FanucRobotServerCommentWritePlan.ps1 -Approved."
    }
    if ([bool]$plan.liveExecutionPerformed) {
        throw "This Robot Server comment write plan appears to have already been marked liveExecutionPerformed=true; generate a fresh plan for another write."
    }
    if (-not $AcceptRobotServerWrite) {
        throw "Robot Server comment write requires -AcceptRobotServerWrite after reviewing the approved plan."
    }
    if ([bool]$plan.operatorApproval.required -and -not $phraseAccepted) {
        throw "Robot Server comment write requires exact -ApprovalPhrase: '$($plan.operatorApproval.requiredPhrase)'"
    }
}

foreach ($write in $writes) {
    $family = [string]$write.family
    $index = [int]$write.index
    $before = $null
    if ($Execute) {
        $before = Get-CurrentComment -HostAddress ([string]$plan.hostAddress) -Family $family -Index $index
    }

    $rowEvidence = [ordered]@{
        family = $family
        index = $index
        name = [string]$write.name
        setFunctionCode = [int]$write.setFunctionCode
        setUrl = [string]$write.setUrl
        before = $before
        plannedCurrent = [string]$write.currentComment
        proposed = [string]$write.proposedComment
        executed = $executed
        writeStatusCode = $null
        after = $null
        verified = $false
    }

    if ($Execute -and $before -ne [string]$write.currentComment) {
        throw "$($write.name) current comment changed since the plan was created. Planned='$($write.currentComment)' Current='$before'."
    }

    if ($Execute) {
        $response = Invoke-WebRequest -Uri ([string]$write.setUrl) -Method Get -TimeoutSec 20 -UseBasicParsing
        $rowEvidence.writeStatusCode = [int]$response.StatusCode
        $after = Get-CurrentComment -HostAddress ([string]$plan.hostAddress) -Family $family -Index $index
        $rowEvidence.after = $after
        $rowEvidence.verified = ($after -eq [string]$write.proposedComment)
        if (-not [bool]$rowEvidence.verified) {
            throw "$($write.name) Robot Server readback mismatch after write. Expected='$($write.proposedComment)' Actual='$after'."
        }
    }

    $evidenceRows.Add([pscustomobject]$rowEvidence)
}

$evidence.rows = $evidenceRows.ToArray()

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$evidence | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

[pscustomobject]@{
    Executed = $executed
    HostAddress = [string]$plan.hostAddress
    WriteCount = $writes.Count
    VerifiedCount = @($evidenceRows | Where-Object { $_.verified }).Count
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
}
