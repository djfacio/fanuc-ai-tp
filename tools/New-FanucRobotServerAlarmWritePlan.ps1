param(
    [string]$AlarmMapPath = "config\alarm-map.psd1",
    [string]$SnapshotPath = "",
    [string]$OutputPath = "generated\metadata\robot-server-alarm-write-plan.json",
    [string]$HostAddress = "",
    [switch]$Approved
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

$severityByName = @{
    "WARN"    = 0
    "STOP.L"  = 6
    "ABORT.L" = 11
    "STOP.G"  = 38
    "ABORT.G" = 43
}

$severityByValue = @{
    0  = "WARN"
    6  = "STOP.L"
    11 = "ABORT.L"
    38 = "STOP.G"
    43 = "ABORT.G"
}

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $projectRoot $Path
}

function Get-AlarmNumber {
    param([object]$Row)

    if ($Row.ContainsKey("AlarmNumber")) {
        return [int]$Row.AlarmNumber
    }
    if ($Row.ContainsKey("Index")) {
        return [int]$Row.Index
    }
    throw "Alarm row is missing AlarmNumber."
}

function ConvertTo-SeverityValue {
    param(
        [object]$Value,
        [string]$FieldName,
        [bool]$Required
    )

    if ($null -eq $Value -or [string]$Value -eq "") {
        if ($Required) {
            throw "$FieldName is required."
        }
        return $null
    }

    $text = ([string]$Value).Trim().ToUpperInvariant()
    $intValue = 0
    if ([int]::TryParse($text, [ref]$intValue)) {
        if (-not $severityByValue.ContainsKey($intValue)) {
            throw "$FieldName severity value $intValue is not in the reviewed set: $(@($severityByValue.Keys | Sort-Object) -join ', ')."
        }
        return $intValue
    }

    if (-not $severityByName.ContainsKey($text)) {
        throw "$FieldName severity '$Value' is not supported. Use one of: $(@($severityByName.Keys | Sort-Object) -join ', ')."
    }

    return [int]$severityByName[$text]
}

function Test-AsciiMessage {
    param(
        [string]$Message,
        [string]$Name
    )

    foreach ($char in $Message.ToCharArray()) {
        $code = [int][char]$char
        if ($code -lt 32 -or $code -gt 126) {
            throw "$Name proposed alarm message contains non-printable or non-ASCII character code $code. Keep Robot Server alarm writes ASCII until encoding is proven."
        }
    }
}

function Get-RowValue {
    param(
        [hashtable]$Row,
        [string[]]$Names
    )

    foreach ($name in $Names) {
        if ($Row.ContainsKey($name)) {
            return $Row[$name]
        }
    }
    return $null
}

$resolvedAlarmMapPath = Resolve-ProjectPath $AlarmMapPath
if (-not (Test-Path -LiteralPath $resolvedAlarmMapPath)) {
    throw "Alarm map not found: $resolvedAlarmMapPath"
}

$alarmMap = Import-PowerShellDataFile -LiteralPath $resolvedAlarmMapPath
if ($null -eq $alarmMap.SchemaVersion -or [int]$alarmMap.SchemaVersion -ne 1) {
    throw "Alarm map SchemaVersion must be 1."
}

if (-not $HostAddress) {
    $robotConfigPath = Join-Path $projectRoot "config\robot.psd1"
    if (Test-Path -LiteralPath $robotConfigPath) {
        $robotConfig = Import-PowerShellDataFile -LiteralPath $robotConfigPath
        $HostAddress = [string]$robotConfig.RobotIp
    }
}
if (-not $HostAddress) {
    throw "HostAddress was not supplied and config\robot.psd1 did not provide RobotIp."
}

$alarmRows = @()
if ($alarmMap.AlarmRows) {
    $alarmRows = @($alarmMap.AlarmRows)
} elseif ($alarmMap.UserAlarmRows) {
    $alarmRows = @($alarmMap.UserAlarmRows)
} else {
    throw "Alarm map must contain AlarmRows or UserAlarmRows."
}

$approvedRows = @($alarmRows | Where-Object { ([string]$_.Status).ToLowerInvariant() -eq "approved" })
$skippedRows = @($alarmRows | Where-Object { ([string]$_.Status).ToLowerInvariant() -ne "approved" })

$snapshot = $null
$snapshotSource = ""
if ($SnapshotPath) {
    $resolvedSnapshotPath = Resolve-ProjectPath $SnapshotPath
    if (-not (Test-Path -LiteralPath $resolvedSnapshotPath)) {
        throw "Snapshot path not found: $resolvedSnapshotPath"
    }
    $snapshot = Get-Content -LiteralPath $resolvedSnapshotPath -Raw | ConvertFrom-Json
    $snapshotSource = (Get-Item -LiteralPath $resolvedSnapshotPath).FullName
} elseif ($approvedRows.Count -gt 0) {
    $reader = Join-Path $scriptRoot "Get-FanucRobotServerMetadata.ps1"
    $minIndex = [int](@($approvedRows | ForEach-Object { Get-AlarmNumber $_ } | Measure-Object -Minimum).Minimum)
    $maxIndex = [int](@($approvedRows | ForEach-Object { Get-AlarmNumber $_ } | Measure-Object -Maximum).Maximum)
    $snapshot = & $reader -HostAddress $HostAddress -Families UALM -StartIndex $minIndex -EndIndex $maxIndex -IncludeValues
    $snapshotSource = "live-robot-server"
} else {
    $snapshot = [pscustomobject]@{
        HostAddress = $HostAddress
        Items = @()
    }
    $snapshotSource = "none-no-approved-rows"
}

$snapshotLookup = @{}
foreach ($item in @($snapshot.Items)) {
    if (([string]$item.Family).ToUpperInvariant() -eq "UALM") {
        $snapshotLookup[[int]$item.Index] = $item
    }
}

$findings = New-Object System.Collections.Generic.List[object]
$writes = New-Object System.Collections.Generic.List[object]
$changeCount = 0

foreach ($rowObject in $approvedRows) {
    $row = [hashtable]$rowObject
    $alarmNumber = Get-AlarmNumber $row
    $name = "UALM[$alarmNumber]"

    if ($alarmNumber -lt 1 -or $alarmNumber -gt 100) {
        throw "$name is outside the supported User Alarm range 1..100."
    }

    $currentItem = $snapshotLookup[$alarmNumber]
    if ($null -eq $currentItem) {
        throw "$name was approved in $resolvedAlarmMapPath but was not present in the current Robot Server snapshot."
    }

    $robotMessage = [string]$currentItem.Comment
    $robotSeverityValue = ConvertTo-SeverityValue -Value $currentItem.Severity -FieldName "$name robot severity" -Required $true
    $robotSeverityName = $severityByValue[$robotSeverityValue]

    if (-not $row.ContainsKey("CurrentMessage")) {
        throw "$name approved row must declare CurrentMessage."
    }
    $declaredMessage = [string]$row.CurrentMessage
    if ($declaredMessage -ne $robotMessage) {
        $findings.Add([pscustomobject]@{
            Rule = "CurrentMessageMismatch"
            Name = $name
            DeclaredCurrent = $declaredMessage
            RobotCurrent = $robotMessage
            Message = "$name current alarm message changed since review."
        })
        continue
    }

    $declaredSeverityRaw = Get-RowValue -Row $row -Names @("CurrentSeverityValue", "CurrentSeverity")
    $declaredSeverityValue = ConvertTo-SeverityValue -Value $declaredSeverityRaw -FieldName "$name CurrentSeverity" -Required $true
    if ($declaredSeverityValue -ne $robotSeverityValue) {
        $findings.Add([pscustomobject]@{
            Rule = "CurrentSeverityMismatch"
            Name = $name
            DeclaredCurrent = $declaredSeverityValue
            RobotCurrent = $robotSeverityValue
            Message = "$name current alarm severity changed since review."
        })
        continue
    }

    $proposedMessageRaw = Get-RowValue -Row $row -Names @("ProposedMessage", "Proposed")
    $hasProposedMessage = ($null -ne $proposedMessageRaw)
    $proposedMessage = if ($hasProposedMessage) { [string]$proposedMessageRaw } else { $robotMessage }
    if ($proposedMessage.Length -gt 29) {
        throw "$name proposed alarm message '$proposedMessage' is $($proposedMessage.Length) characters; Robot Server limit is 29."
    }
    Test-AsciiMessage -Message $proposedMessage -Name $name

    $proposedSeverityRaw = Get-RowValue -Row $row -Names @("ProposedSeverityValue", "ProposedSeverity")
    $hasProposedSeverity = ($null -ne $proposedSeverityRaw -and [string]$proposedSeverityRaw -ne "")
    $proposedSeverityValue = if ($hasProposedSeverity) {
        ConvertTo-SeverityValue -Value $proposedSeverityRaw -FieldName "$name ProposedSeverity" -Required $true
    } else {
        $robotSeverityValue
    }
    $proposedSeverityName = $severityByValue[$proposedSeverityValue]

    if (-not $hasProposedMessage -and -not $hasProposedSeverity) {
        throw "$name approved row must propose a message, a severity, or both."
    }

    $messageWrite = $null
    if ($hasProposedMessage -and $proposedMessage -ne $robotMessage) {
        $encodedMessage = [System.Uri]::EscapeDataString($proposedMessage)
        $messageWrite = [ordered]@{
            field = "message"
            setFunctionCode = 4
            setUrl = "http://$HostAddress/KAREL/ComSet?sComment=$encodedMessage&sIndx=$alarmNumber&sFc=4"
        }
        $changeCount++
    }

    $severityWrite = $null
    if ($hasProposedSeverity -and $proposedSeverityValue -ne $robotSeverityValue) {
        $severityWrite = [ordered]@{
            field = "severity"
            setFunctionCode = 5
            setUrl = "http://$HostAddress/KAREL/ComSet?sValue=$proposedSeverityValue&sIndx=$alarmNumber&sFc=5"
        }
        $changeCount++
    }

    if ($null -eq $messageWrite -and $null -eq $severityWrite) {
        $findings.Add([pscustomobject]@{
            Rule = "AlreadyMatches"
            Name = $name
            Message = "$name already matches approved alarm metadata."
        })
        continue
    }

    $writes.Add([pscustomobject]([ordered]@{
        alarmNumber = $alarmNumber
        name = $name
        currentMessage = $robotMessage
        proposedMessage = $proposedMessage
        currentSeverityValue = $robotSeverityValue
        currentSeverityName = $robotSeverityName
        proposedSeverityValue = $proposedSeverityValue
        proposedSeverityName = $proposedSeverityName
        source = [string]$row.Source
        reason = [string]$row.Reason
        getFunctionCode = 31
        messageWrite = $messageWrite
        severityWrite = $severityWrite
    }))
}

if ($findings.Count -gt 0) {
    $blocking = @($findings | Where-Object { $_.Rule -in @("CurrentMessageMismatch", "CurrentSeverityMismatch") })
    if ($blocking.Count -gt 0) {
        $messages = @($blocking | ForEach-Object { "- $($_.Message) Declared='$($_.DeclaredCurrent)' Robot='$($_.RobotCurrent)'" })
        throw "Robot Server alarm write plan blocked by current metadata mismatch:`n$($messages -join "`n")"
    }
}

$approvalPhrase = "I approve Robot Server alarm writes: $changeCount change(s) across $($writes.Count) alarm(s) to $HostAddress"
$plan = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    approvedForLive = [bool]$Approved
    liveExecutionPerformed = $false
    hostAddress = $HostAddress
    alarmMapPath = (Get-Item -LiteralPath $resolvedAlarmMapPath).FullName
    snapshotSource = $snapshotSource
    approvedRowCount = $approvedRows.Count
    skippedRowCount = $skippedRows.Count
    writeRowCount = $writes.Count
    changeCount = $changeCount
    writes = $writes.ToArray()
    findings = $findings.ToArray()
    operatorApproval = [ordered]@{
        required = $true
        requiredPhrase = $approvalPhrase
        warning = "Review every alarm number, current/proposed message, current/proposed severity, and exact ComSet URL before live execution."
    }
    executionGate = [ordered]@{
        userAlarmsOnly = $true
        usesRobotServerComSet = $true
        allowedFunctionCodes = @(4, 5)
        mustUseExactApprovalPhrase = $true
        mustReadBackAfterWrite = $true
        excludesCommentsAndValues = $true
    }
}

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

[pscustomobject]@{
    ApprovedForLive = [bool]$Approved
    HostAddress = $HostAddress
    ApprovedRows = $approvedRows.Count
    SkippedRows = $skippedRows.Count
    WriteRows = $writes.Count
    ChangeCount = $changeCount
    ApprovalPhrase = $approvalPhrase
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
}
