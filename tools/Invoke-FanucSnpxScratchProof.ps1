param(
    [Parameter(Mandatory = $true)]
    [string]$Fanuc,

    [object]$Value,

    [string]$State,

    [string]$ConfigPath = "..\config\snpx-writes.psd1",
    [string]$ReadConfigPath = "..\config\snpx-readonly.psd1",
    [string]$OutputRoot = "generated\cell-status\scratch-proofs",
    [string]$HostAddress,
    [string]$ApprovalPhrase,
    [switch]$Execute
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

function Get-SafeName {
    param([string]$Text)

    $safe = $Text.ToUpperInvariant() -replace '[^A-Z0-9]+', '-'
    $safe = $safe.Trim('-')
    if ($safe.Length -eq 0) {
        return "SNPX-PROOF"
    }
    return $safe
}

$planner = Join-Path $scriptRoot "New-FanucSnpxWritePlan.ps1"
$liveWriter = Join-Path $scriptRoot "Invoke-FanucSnpxLiveWrite.ps1"

$safeFanuc = Get-SafeName -Text $Fanuc
$stamp = (Get-Date).ToString("yyyyMMdd-HHmmss-ffff")
$resolvedOutputRoot = Resolve-ProjectPath $OutputRoot
$bundleDir = Join-Path $resolvedOutputRoot "$stamp-$safeFanuc"
if (-not (Test-Path -LiteralPath $bundleDir)) {
    New-Item -ItemType Directory -Path $bundleDir -Force | Out-Null
}

$planPath = Join-Path $bundleDir "plan.json"
$evidencePath = Join-Path $bundleDir "live-write.json"
$summaryPath = Join-Path $bundleDir "summary.json"
$summaryMarkdownPath = Join-Path $bundleDir "summary.md"

$planParams = @{
    Fanuc = $Fanuc
    ConfigPath = $ConfigPath
    OutputPath = $planPath
    Approved = $true
}
if ($PSBoundParameters.ContainsKey("Value")) {
    $planParams.Value = $Value
}
if ($State) {
    $planParams.State = $State
}

$planResult = & $planner @planParams
$plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
$requiredPhrase = [string]$plan.operatorApproval.requiredPhrase

if ($Execute -and $ApprovalPhrase -ne $requiredPhrase) {
    throw "Live scratch proof requires exact -ApprovalPhrase: '$requiredPhrase'"
}

$liveParams = @{
    PlanPath = $planPath
    ReadConfigPath = $ReadConfigPath
    OutputPath = $evidencePath
}
if ($HostAddress) {
    $liveParams.HostAddress = $HostAddress
}
if ($ApprovalPhrase) {
    $liveParams.ApprovalPhrase = $ApprovalPhrase
}
if ($Execute) {
    $liveParams.Execute = $true
    $liveParams.AcceptLiveWrite = $true
    if ([bool]$plan.restoration.required) {
        $liveParams.RestoreAfterWrite = $true
    }
}

$liveResult = & $liveWriter @liveParams
$evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json

$summary = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    executed = [bool]$Execute
    fanuc = $plan.write.fanuc
    value = $plan.write.value
    type = $plan.write.type
    dynamicProjection = [bool]$plan.write.dynamicProjection
    snpxAddress = $plan.write.snpxAddress
    snpxStart = $liveResult.Start
    approvalPhrase = $requiredPhrase
    approvalAccepted = [bool]$evidence.operatorApproval.phraseAccepted
    restorationRequired = [bool]$plan.restoration.required
    restoredAfterWrite = [bool]$liveResult.RestoredAfterWrite
    planPath = (Get-Item -LiteralPath $planPath).FullName
    evidencePath = (Get-Item -LiteralPath $evidencePath).FullName
}

$summary | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding ASCII

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# SNPX Scratch Proof")
$lines.Add("")
$lines.Add("- FANUC: $($summary.fanuc)")
$lines.Add("- Value: $($summary.value)")
$lines.Add("- Executed: $($summary.executed)")
$lines.Add("- Dynamic projection: $($summary.dynamicProjection)")
$lines.Add("- SNPX projection: $($summary.snpxAddress)")
$lines.Add("- Restoration required: $($summary.restorationRequired)")
$lines.Add("- Restored after write: $($summary.restoredAfterWrite)")
$lines.Add("")
$lines.Add("## Approval")
$lines.Add("")
$lines.Add("Required phrase:")
$lines.Add("")
$lines.Add('```text')
$lines.Add($requiredPhrase)
$lines.Add('```')
$lines.Add("")
$lines.Add("## Evidence")
$lines.Add("")
$lines.Add("- Plan: $($summary.planPath)")
$lines.Add("- Live write: $($summary.evidencePath)")
$lines | Set-Content -LiteralPath $summaryMarkdownPath -Encoding ASCII

[pscustomobject]@{
    Executed = [bool]$Execute
    Fanuc = $summary.fanuc
    Value = $summary.value
    DynamicProjection = [bool]$summary.dynamicProjection
    SnpxAddress = $summary.snpxAddress
    RequiresRestoration = [bool]$summary.restorationRequired
    RestoredAfterWrite = [bool]$summary.restoredAfterWrite
    ApprovalPhrase = $requiredPhrase
    BundlePath = (Get-Item -LiteralPath $bundleDir).FullName
    SummaryPath = (Get-Item -LiteralPath $summaryPath).FullName
    SummaryMarkdownPath = (Get-Item -LiteralPath $summaryMarkdownPath).FullName
}
