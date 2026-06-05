param(
    [string]$PlanPath = "generated\metadata\robot-server-alarm-write-plan.json",
    [string]$OutputPath = "generated\metadata\robot-server-alarm-write-evidence.json",
    [string]$ApprovalPhrase = "",
    [switch]$Execute,
    [switch]$AcceptRobotServerAlarmWrite
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

function Get-CurrentAlarm {
    param(
        [string]$HostAddress,
        [int]$AlarmNumber
    )

    $reader = Join-Path $scriptRoot "Get-FanucRobotServerMetadata.ps1"
    $snapshot = & $reader -HostAddress $HostAddress -Families UALM -StartIndex $AlarmNumber -EndIndex $AlarmNumber -IncludeValues
    $item = @($snapshot.Items | Where-Object { ([string]$_.Family).ToUpperInvariant() -eq "UALM" -and [int]$_.Index -eq $AlarmNumber } | Select-Object -First 1)
    if (-not $item) {
        throw "Readback did not find UALM[$AlarmNumber]."
    }
    return [pscustomobject]@{
        Message = [string]$item.Comment
        SeverityValue = [int]$item.Severity
        SeverityName = [string]$item.SeverityName
    }
}

$resolvedPlanPath = Resolve-ProjectPath $PlanPath
if (-not (Test-Path -LiteralPath $resolvedPlanPath)) {
    throw "Robot Server alarm write plan not found: $resolvedPlanPath"
}

$plan = Get-Content -LiteralPath $resolvedPlanPath -Raw | ConvertFrom-Json
if (-not [bool]$plan.executionGate.userAlarmsOnly) {
    throw "Plan does not declare userAlarmsOnly=true."
}

$writes = @($plan.writes)
$evidenceRows = New-Object System.Collections.Generic.List[object]
$executed = [bool]$Execute
$phraseAccepted = (-not [bool]$plan.operatorApproval.required -or $ApprovalPhrase -eq [string]$plan.operatorApproval.requiredPhrase)

$evidence = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    executed = $executed
    acceptedRobotServerAlarmWrite = [bool]$AcceptRobotServerAlarmWrite
    hostAddress = [string]$plan.hostAddress
    planPath = (Get-Item -LiteralPath $resolvedPlanPath).FullName
    writeRowCount = $writes.Count
    changeCount = [int]$plan.changeCount
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
        throw "Robot Server alarm write plan is not approved for live execution. Regenerate with New-FanucRobotServerAlarmWritePlan.ps1 -Approved."
    }
    if ([bool]$plan.liveExecutionPerformed) {
        throw "This Robot Server alarm write plan appears to have already been marked liveExecutionPerformed=true; generate a fresh plan for another write."
    }
    if (-not $AcceptRobotServerAlarmWrite) {
        throw "Robot Server alarm write requires -AcceptRobotServerAlarmWrite after reviewing the approved plan."
    }
    if ([bool]$plan.operatorApproval.required -and -not $phraseAccepted) {
        throw "Robot Server alarm write requires exact -ApprovalPhrase: '$($plan.operatorApproval.requiredPhrase)'"
    }
}

foreach ($write in $writes) {
    $alarmNumber = [int]$write.alarmNumber
    $before = $null
    if ($Execute) {
        $before = Get-CurrentAlarm -HostAddress ([string]$plan.hostAddress) -AlarmNumber $alarmNumber
    }

    $rowEvidence = [ordered]@{
        alarmNumber = $alarmNumber
        name = [string]$write.name
        beforeMessage = if ($before) { $before.Message } else { $null }
        beforeSeverityValue = if ($before) { $before.SeverityValue } else { $null }
        plannedCurrentMessage = [string]$write.currentMessage
        plannedCurrentSeverityValue = [int]$write.currentSeverityValue
        proposedMessage = [string]$write.proposedMessage
        proposedSeverityValue = [int]$write.proposedSeverityValue
        messageSetUrl = if ($write.messageWrite) { [string]$write.messageWrite.setUrl } else { $null }
        severitySetUrl = if ($write.severityWrite) { [string]$write.severityWrite.setUrl } else { $null }
        executed = $executed
        messageWriteStatusCode = $null
        severityWriteStatusCode = $null
        afterMessage = $null
        afterSeverityValue = $null
        verified = $false
    }

    if ($Execute) {
        if ($before.Message -ne [string]$write.currentMessage) {
            throw "$($write.name) current alarm message changed since the plan was created. Planned='$($write.currentMessage)' Current='$($before.Message)'."
        }
        if ($before.SeverityValue -ne [int]$write.currentSeverityValue) {
            throw "$($write.name) current alarm severity changed since the plan was created. Planned='$($write.currentSeverityValue)' Current='$($before.SeverityValue)'."
        }

        if ($write.messageWrite) {
            $response = Invoke-WebRequest -Uri ([string]$write.messageWrite.setUrl) -Method Get -TimeoutSec 20 -UseBasicParsing
            $rowEvidence.messageWriteStatusCode = [int]$response.StatusCode
        }
        if ($write.severityWrite) {
            $response = Invoke-WebRequest -Uri ([string]$write.severityWrite.setUrl) -Method Get -TimeoutSec 20 -UseBasicParsing
            $rowEvidence.severityWriteStatusCode = [int]$response.StatusCode
        }

        $after = Get-CurrentAlarm -HostAddress ([string]$plan.hostAddress) -AlarmNumber $alarmNumber
        $rowEvidence.afterMessage = $after.Message
        $rowEvidence.afterSeverityValue = $after.SeverityValue
        $rowEvidence.verified = (
            $after.Message -eq [string]$write.proposedMessage -and
            $after.SeverityValue -eq [int]$write.proposedSeverityValue
        )
        if (-not [bool]$rowEvidence.verified) {
            throw "$($write.name) Robot Server readback mismatch after alarm write. Expected message='$($write.proposedMessage)' severity='$($write.proposedSeverityValue)' Actual message='$($after.Message)' severity='$($after.SeverityValue)'."
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

$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

[pscustomobject]@{
    Executed = $executed
    HostAddress = [string]$plan.hostAddress
    WriteRows = $writes.Count
    ChangeCount = [int]$plan.changeCount
    VerifiedCount = @($evidenceRows | Where-Object { $_.verified }).Count
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
}
