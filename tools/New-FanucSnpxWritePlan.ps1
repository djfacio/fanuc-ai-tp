param(
    [Parameter(Mandatory = $true)]
    [string]$Fanuc,

    [object]$Value,

    [string]$State,

    [string]$ConfigPath = "..\config\snpx-writes.psd1",
    [string]$OutputPath = "generated\cell-status\snpx-write-plan.json",
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

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

$validator = Join-Path $scriptRoot "Test-FanucSnpxWriteConfig.ps1"
& $validator -ConfigPath $resolvedConfig -Quiet

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig
$fanucKey = $Fanuc.ToUpperInvariant()
$entry = $null
foreach ($candidate in @($config.AllowedWrites)) {
    if ($candidate.Fanuc.ToUpperInvariant() -eq $fanucKey) {
        $entry = $candidate
        break
    }
}

if ($null -eq $entry) {
    throw "SNPX write '$Fanuc' is not allowlisted in $($resolvedConfig.Path)."
}

$plannedValue = $null
$encodedWords = @()
$restorationRequired = $false
$restorationValue = $null
$restorationEncodedWords = @()
switch ($entry.Type) {
    "int" {
        if ($null -eq $Value) {
            throw "SNPX integer write '$fanucKey' requires -Value."
        }

        $intValue = [int]$Value
        if ($intValue -lt [int]$entry.Min -or $intValue -gt [int]$entry.Max) {
            throw "SNPX integer write '$fanucKey' value $intValue is outside allowed range $($entry.Min)..$($entry.Max)."
        }

        $plannedValue = $intValue
        $unsignedValue = [uint32]$intValue
        $encodedWords = @(
            ([int]($unsignedValue -band 0xFFFF)),
            ([int](($unsignedValue -shr 16) -band 0xFFFF))
        )
    }
    "bool" {
        if (-not $State) {
            throw "SNPX boolean write '$fanucKey' requires -State ON or OFF."
        }

        $stateText = $State.ToUpperInvariant()
        if (@($entry.AllowedStates | ForEach-Object { $_.ToUpperInvariant() }) -notcontains $stateText) {
            throw "SNPX boolean write '$fanucKey' state '$State' is not allowlisted."
        }

        $plannedValue = $stateText
        $boolWord = if ($stateText -eq "ON") { 1 } else { 0 }
        $encodedWords = @(
            $boolWord,
            0
        )

        if ($stateText -eq "ON" -and @($entry.AllowedStates | ForEach-Object { $_.ToUpperInvariant() }) -contains "OFF") {
            $restorationRequired = $true
            $restorationValue = "OFF"
            $restorationEncodedWords = @(0, 0)
        }
    }
    default {
        throw "SNPX write type '$($entry.Type)' is valid in config but not implemented by this plan tool yet."
    }
}

$approvalValue = if ($entry.Type -eq "bool") { [string]$plannedValue } else { [string]$plannedValue }
$approvalPhrase = "I approve live SNPX write: $($entry.Fanuc)=$approvalValue via $($entry.SnpxAddress)"

$plan = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    approvedForLive = [bool]$Approved
    liveExecutionImplemented = $false
    configPath = (Get-Item -LiteralPath $resolvedConfig).FullName
    protocol = $config.Protocol
    mappingMode = $config.MappingMode
    defaultMode = $config.DefaultMode
    write = [ordered]@{
        name = $entry.Name
        fanuc = $entry.Fanuc
        type = $entry.Type
        value = $plannedValue
        transport = $entry.Transport
        snpxAddress = $entry.SnpxAddress
        wordCount = [int]$entry.WordCount
        encodedWords = $encodedWords
        requiresHumanApproval = [bool]$config.RequireHumanApproval
        requiresLiveProof = [bool]$entry.RequiresLiveProof
        notes = $entry.Notes
    }
    operatorApproval = [ordered]@{
        required = [bool]$config.RequireHumanApproval
        requiredPhrase = $approvalPhrase
        warning = "Review the target, value, SNPX projection, encoded words, and restoration section before live execution."
    }
    restoration = [ordered]@{
        required = [bool]$restorationRequired
        reason = if ($restorationRequired) { "Output write requests ON and must be restored to OFF after proof." } else { "No automatic restoration required for this planned value." }
        fanuc = if ($restorationRequired) { $entry.Fanuc } else { $null }
        value = $restorationValue
        encodedWords = $restorationEncodedWords
    }
    executionGate = [ordered]@{
        mustProgramPrivateAsg = $true
        mustVerifyAsgReadback = $true
        mustReadBeforeWrite = $true
        mustReadAfterWrite = $true
        mustUseExactApprovalPhrase = [bool]$config.RequireHumanApproval
        mustRestoreAfterWrite = [bool]$restorationRequired
        mustReadAfterRestore = [bool]$restorationRequired
        snapshotToolRemainsReadOnly = $true
    }
}

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

[pscustomobject]@{
    Fanuc = $entry.Fanuc
    Type = $entry.Type
    Value = $plannedValue
    SnpxAddress = $entry.SnpxAddress
    ApprovedForLive = [bool]$Approved
    LiveExecutionImplemented = $false
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
}
