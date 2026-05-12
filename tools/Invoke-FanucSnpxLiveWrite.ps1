param(
    [string]$PlanPath = "generated\cell-status\snpx-write-plan.json",
    [string]$ReadConfigPath = "..\config\snpx-readonly.psd1",
    [string]$OutputPath = "generated\cell-status\snpx-live-write.json",
    [string]$HostAddress,
    [switch]$Execute,
    [switch]$AcceptLiveWrite
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

function Invoke-CodecToolJson {
    param([hashtable]$Parameters)

    $tool = Join-Path $scriptRoot "Invoke-FanucSnpxCodecTool.ps1"
    $output = & $tool @Parameters
    if ($LASTEXITCODE -ne 0) {
        throw "SNPX codec tool failed with exit code $LASTEXITCODE.`n$($output -join "`n")"
    }

    $jsonLine = @($output | Where-Object { $_ -match '^\s*\{' } | Select-Object -Last 1)
    if (-not $jsonLine) {
        throw "SNPX codec tool did not emit JSON.`n$($output -join "`n")"
    }

    return ($jsonLine | ConvertFrom-Json)
}

$resolvedPlanPath = Resolve-ProjectPath $PlanPath
if (-not (Test-Path -LiteralPath $resolvedPlanPath)) {
    throw "SNPX write plan not found: $resolvedPlanPath"
}

$plan = Get-Content -LiteralPath $resolvedPlanPath -Raw | ConvertFrom-Json
if (-not [bool]$plan.approvedForLive) {
    throw "SNPX write plan is not approved for live execution. Regenerate with New-FanucSnpxWritePlan.ps1 -Approved."
}

if ([bool]$plan.liveExecutionImplemented) {
    throw "This plan appears to have already been marked liveExecutionImplemented=true; generate a fresh plan for another write."
}

if ($plan.write.type -notin @("int", "bool")) {
    throw "Live SNPX write execution currently supports integer and boolean ASG writes only. Requested '$($plan.write.type)'."
}

if ([System.IO.Path]::IsPathRooted($ReadConfigPath)) {
    $resolvedReadConfig = Resolve-Path -LiteralPath $ReadConfigPath
} else {
    $resolvedReadConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ReadConfigPath)
}

$readValidator = Join-Path $scriptRoot "Test-FanucSnpxReadonlyConfig.ps1"
& $readValidator -ConfigPath $resolvedReadConfig -Quiet
$readConfig = Import-PowerShellDataFile -LiteralPath $resolvedReadConfig

if (-not $HostAddress) {
    $HostAddress = "$($readConfig.RobotIp):$($readConfig.Port)"
}

$probes = @($readConfig.SystemProbes | Sort-Object { [int]$_.SnpxStart })
$reads = @($readConfig.Reads | Sort-Object { [int]$_.SnpxStart })
$setasgEntries = @($probes + $reads)
$setasg = @($setasgEntries | ForEach-Object {
    "SETASG $($_.SnpxStart) $($_.WordCount) $($_.SetAsgRegion) $($_.SetAsgMultiply)"
})

$mappedRead = @($reads | Where-Object { $_.Fanuc.ToUpperInvariant() -eq $plan.write.fanuc.ToUpperInvariant() } | Select-Object -First 1)
if (-not $mappedRead) {
    throw "SNPX write target '$($plan.write.fanuc)' is not present in $($resolvedReadConfig.Path)."
}

if ($mappedRead.SnpxAddress -ne $plan.write.snpxAddress) {
    throw "Plan maps $($plan.write.fanuc) to $($plan.write.snpxAddress), but read config maps it to $($mappedRead.SnpxAddress)."
}

$setupPath = Resolve-ProjectPath "generated\cell-status\snpx-asg-commands.txt"
$setupDir = Split-Path -Parent $setupPath
if (-not (Test-Path -LiteralPath $setupDir)) {
    New-Item -ItemType Directory -Path $setupDir -Force | Out-Null
}
$setasg | Set-Content -LiteralPath $setupPath -Encoding ASCII

$writeValue = $null
if ($plan.write.type -eq "bool") {
    $writeState = ([string]$plan.write.value).ToUpperInvariant()
    if ($writeState -eq "ON") {
        $writeValue = 1
    } elseif ($writeState -eq "OFF") {
        $writeValue = 0
    } else {
        throw "Boolean SNPX write value must be ON or OFF. Saw '$($plan.write.value)'."
    }
} else {
    $writeValue = [int]$plan.write.value
}

$evidence = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    executed = [bool]$Execute
    acceptedLiveWrite = [bool]$AcceptLiveWrite
    hostAddress = $HostAddress
    planPath = (Get-Item -LiteralPath $resolvedPlanPath).FullName
    readConfigPath = (Get-Item -LiteralPath $resolvedReadConfig).FullName
    commands = [ordered]@{
        clrasg = "CLRASG"
        setasg = $setasg
        setupFile = (Get-Item -LiteralPath $setupPath).FullName
        write = [ordered]@{
            operation = "asg-write-r"
            fanuc = $plan.write.fanuc
            snpxAddress = $plan.write.snpxAddress
            start = [int]$mappedRead.SnpxStart
            value = $plan.write.value
            encodedValue = [int]$writeValue
        }
    }
    results = [ordered]@{}
}

if ($Execute) {
    if (-not $AcceptLiveWrite) {
        throw "Live SNPX write requires -AcceptLiveWrite after reviewing the approved plan."
    }

    $writeResult = Invoke-CodecToolJson -Parameters @{
        Operation = "asg-write-r"
        HostAddress = $HostAddress
        SetupFile = $setupPath
        Start = [int]$mappedRead.SnpxStart
        Value = [int]$writeValue
        AcceptLiveWrite = $true
    }

    $evidence.results.write = $writeResult
    $after = @($writeResult.after)
    if ($after.Count -lt 1 -or [int]$after[0] -ne [int]$writeValue) {
        throw "SNPX live write did not read back expected encoded value $writeValue for $($plan.write.fanuc)."
    }
}

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

[pscustomobject]@{
    Executed = [bool]$Execute
    Fanuc = $plan.write.fanuc
    Value = $plan.write.value
    EncodedValue = [int]$writeValue
    SnpxAddress = $plan.write.snpxAddress
    Start = [int]$mappedRead.SnpxStart
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
}
