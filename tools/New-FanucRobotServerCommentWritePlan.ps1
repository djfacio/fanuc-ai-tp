param(
    [string]$CommentMapPath = "config\comment-map.psd1",
    [string]$SnapshotPath = "",
    [string]$OutputPath = "generated\metadata\robot-server-comment-write-plan.json",
    [string]$HostAddress = "",
    [switch]$Approved
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

function Get-CommentLimit {
    param([string]$Family)

    switch ($Family) {
        "R" { return 16 }
        "PR" { return 16 }
        "SR" { return 16 }
        "RI" { return 16 }
        "RO" { return 16 }
        "DI" { return 16 }
        "DO" { return 16 }
        "GI" { return 16 }
        "GO" { return 16 }
        "AI" { return 16 }
        "AO" { return 16 }
        "F" { return 16 }
        default { throw "Unsupported comment family '$Family'." }
    }
}

function Get-ComSetFunction {
    param([string]$Family)

    switch ($Family) {
        "R" { return 1 }
        "PR" { return 3 }
        "RI" { return 6 }
        "RO" { return 7 }
        "DI" { return 8 }
        "DO" { return 9 }
        "GI" { return 10 }
        "GO" { return 11 }
        "AI" { return 12 }
        "AO" { return 13 }
        "SR" { return 14 }
        "F" { return 19 }
        default { throw "Unsupported comment family '$Family'." }
    }
}

function Get-ComGetFunction {
    param([string]$Family)

    switch ($Family) {
        "R" { return 28 }
        "PR" { return 29 }
        "SR" { return 30 }
        "RI" { return 32 }
        "RO" { return 32 }
        "DI" { return 33 }
        "DO" { return 33 }
        "GI" { return 34 }
        "GO" { return 34 }
        "AI" { return 35 }
        "AO" { return 35 }
        "F" { return 76 }
        default { throw "Unsupported comment family '$Family'." }
    }
}

function Get-ResourceName {
    param(
        [string]$Family,
        [int]$Index
    )

    return "$Family[$Index]"
}

function Test-AsciiComment {
    param(
        [string]$Comment,
        [string]$Name
    )

    foreach ($char in $Comment.ToCharArray()) {
        $code = [int][char]$char
        if ($code -lt 32 -or $code -gt 126) {
            throw "$Name proposed comment contains non-printable or non-ASCII character code $code. Keep Robot Server comment writes ASCII until encoding is proven."
        }
    }
}

$resolvedCommentMapPath = Resolve-ProjectPath $CommentMapPath
if (-not (Test-Path -LiteralPath $resolvedCommentMapPath)) {
    throw "Comment map not found: $resolvedCommentMapPath"
}

$commentMap = Import-PowerShellDataFile -LiteralPath $resolvedCommentMapPath
if ($null -eq $commentMap.SchemaVersion -or [int]$commentMap.SchemaVersion -ne 1) {
    throw "Comment map SchemaVersion must be 1."
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

$approvedRows = @($commentMap.CommentRows | Where-Object { ([string]$_.Status).ToLowerInvariant() -eq "approved" })
$skippedRows = @($commentMap.CommentRows | Where-Object { ([string]$_.Status).ToLowerInvariant() -ne "approved" })

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
    $families = @($approvedRows | ForEach-Object { ([string]$_.Family).ToUpperInvariant() } | Select-Object -Unique)
    $minIndex = [int](@($approvedRows | ForEach-Object { [int]$_.Index } | Measure-Object -Minimum).Minimum)
    $maxIndex = [int](@($approvedRows | ForEach-Object { [int]$_.Index } | Measure-Object -Maximum).Maximum)
    $snapshot = & $reader -HostAddress $HostAddress -Families $families -StartIndex $minIndex -EndIndex $maxIndex
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
    $key = "$(([string]$item.Family).ToUpperInvariant())[$([int]$item.Index)]"
    $snapshotLookup[$key] = $item
}

$findings = New-Object System.Collections.Generic.List[object]
$writes = New-Object System.Collections.Generic.List[object]

foreach ($row in $approvedRows) {
    $family = ([string]$row.Family).ToUpperInvariant()
    $index = [int]$row.Index
    $name = Get-ResourceName -Family $family -Index $index
    $proposed = [string]$row.Proposed
    $declaredCurrent = [string]$row.Current

    if ($family -in @("UALM", "UI", "UO")) {
        throw "$name is not supported by the first Robot Server comment writer. User alarms and UOP comments need a separate lane."
    }

    $limit = Get-CommentLimit -Family $family
    if ($proposed.Length -gt $limit) {
        throw "$name proposed comment '$proposed' is $($proposed.Length) characters; Robot Server limit for $family is $limit."
    }
    Test-AsciiComment -Comment $proposed -Name $name

    $currentItem = $snapshotLookup[$name]
    if ($null -eq $currentItem) {
        throw "$name was approved in $resolvedCommentMapPath but was not present in the current Robot Server snapshot."
    }
    $current = [string]$currentItem.Comment

    if ($declaredCurrent -ne "" -and $declaredCurrent -ne $current) {
        $findings.Add([pscustomobject]@{
            Rule = "CurrentCommentMismatch"
            Name = $name
            DeclaredCurrent = $declaredCurrent
            RobotCurrent = $current
            Message = "$name current comment changed since review."
        })
        continue
    }

    if ($current -eq $proposed) {
        $findings.Add([pscustomobject]@{
            Rule = "AlreadyMatches"
            Name = $name
            Message = "$name already has approved comment '$proposed'."
        })
        continue
    }

    $setFunction = Get-ComSetFunction -Family $family
    $getFunction = Get-ComGetFunction -Family $family
    $encodedComment = [System.Uri]::EscapeDataString($proposed)
    $setUrl = "http://$HostAddress/KAREL/ComSet?sComment=$encodedComment&sIndx=$index&sFc=$setFunction"

    $writes.Add([pscustomobject]([ordered]@{
        family = $family
        index = $index
        name = $name
        currentComment = $current
        proposedComment = $proposed
        maxLength = $limit
        source = [string]$row.Source
        reason = [string]$row.Reason
        getFunctionCode = $getFunction
        setFunctionCode = $setFunction
        setUrl = $setUrl
    }))
}

if ($findings.Count -gt 0) {
    $blocking = @($findings | Where-Object { $_.Rule -eq "CurrentCommentMismatch" })
    if ($blocking.Count -gt 0) {
        $messages = @($blocking | ForEach-Object { "- $($_.Message) Declared='$($_.DeclaredCurrent)' Robot='$($_.RobotCurrent)'" })
        throw "Robot Server comment write plan blocked by current-comment mismatch:`n$($messages -join "`n")"
    }
}

$approvalPhrase = "I approve Robot Server comment writes: $($writes.Count) row(s) to $HostAddress"
$plan = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    approvedForLive = [bool]$Approved
    liveExecutionPerformed = $false
    hostAddress = $HostAddress
    commentMapPath = (Get-Item -LiteralPath $resolvedCommentMapPath).FullName
    snapshotSource = $snapshotSource
    approvedRowCount = $approvedRows.Count
    skippedRowCount = $skippedRows.Count
    writeCount = $writes.Count
    writes = $writes.ToArray()
    findings = $findings.ToArray()
    operatorApproval = [ordered]@{
        required = $true
        requiredPhrase = $approvalPhrase
        warning = "Review every family/index/current/proposed comment and exact ComSet URL before live execution."
    }
    executionGate = [ordered]@{
        commentsOnly = $true
        usesRobotServerComSet = $true
        mustUseExactApprovalPhrase = $true
        mustReadBackAfterWrite = $true
        excludedFunctionCodes = @(2, 4, 5, 15, 16, 17, 18, 67, 68, 69, 70)
    }
}

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

[pscustomobject]@{
    ApprovedForLive = [bool]$Approved
    HostAddress = $HostAddress
    ApprovedRows = $approvedRows.Count
    SkippedRows = $skippedRows.Count
    WriteCount = $writes.Count
    ApprovalPhrase = $approvalPhrase
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
}
