param(
    [string]$PlanPath = "generated\cell-status\snpx-write-plan.json",
    [string]$ReadConfigPath = "..\config\snpx-readonly.psd1",
    [string]$OutputPath = "generated\cell-status\snpx-live-write.json",
    [string]$HostAddress,
    [string]$ApprovalPhrase,
    [switch]$Execute,
    [switch]$AcceptLiveWrite,
    [switch]$RestoreAfterWrite
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

function Convert-ToUInt16Word {
    param([object]$Value)

    $intValue = [int]$Value
    return [int]([uint16]$intValue)
}

function Assert-EncodedWordsReadBack {
    param(
        [object[]]$Actual,
        [object[]]$Expected,
        [string]$Context
    )

    if (@($Actual).Count -lt @($Expected).Count) {
        throw "$Context readback returned $(@($Actual).Count) word(s), expected $(@($Expected).Count)."
    }

    for ($index = 0; $index -lt @($Expected).Count; $index++) {
        $actualWord = Convert-ToUInt16Word -Value $Actual[$index]
        $expectedWord = Convert-ToUInt16Word -Value $Expected[$index]
        if ($actualWord -ne $expectedWord) {
            throw "$Context readback word $index was $actualWord, expected $expectedWord."
        }
    }
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

$usesDynamicProjection = [bool]$plan.write.dynamicProjection
$writeStart = $null

if ($usesDynamicProjection) {
    if ($null -eq $plan.write.snpxStart -or [int]$plan.write.snpxStart -lt 1) {
        throw "Dynamic SNPX write plan for $($plan.write.fanuc) is missing snpxStart."
    }
    if ($null -eq $plan.write.setAsgRegion -or [string]$plan.write.setAsgRegion -ne [string]$plan.write.fanuc) {
        throw "Dynamic SNPX write plan for $($plan.write.fanuc) must map setAsgRegion to the same FANUC target."
    }
    if ($null -eq $plan.write.setAsgMultiply -or [int]$plan.write.setAsgMultiply -lt 1) {
        throw "Dynamic SNPX write plan for $($plan.write.fanuc) is missing setAsgMultiply."
    }

    $dynamicStart = [int]$plan.write.snpxStart
    $dynamicEnd = $dynamicStart + [int]$plan.write.wordCount - 1
    foreach ($read in $reads) {
        $readStart = [int]$read.SnpxStart
        $readEnd = $readStart + [int]$read.WordCount - 1
        if ($dynamicStart -le $readEnd -and $readStart -le $dynamicEnd) {
            throw "Dynamic SNPX write projection $($plan.write.snpxAddress) overlaps read mapping '$($read.Fanuc)'."
        }
    }

    $setasg += "SETASG $dynamicStart $($plan.write.wordCount) $($plan.write.setAsgRegion) $($plan.write.setAsgMultiply)"
    $writeStart = $dynamicStart
} else {
    $mappedRead = @($reads | Where-Object { $_.Fanuc.ToUpperInvariant() -eq $plan.write.fanuc.ToUpperInvariant() } | Select-Object -First 1)
    if (-not $mappedRead) {
        throw "SNPX write target '$($plan.write.fanuc)' is not present in $($resolvedReadConfig.Path)."
    }

    if ($mappedRead.SnpxAddress -ne $plan.write.snpxAddress) {
        throw "Plan maps $($plan.write.fanuc) to $($plan.write.snpxAddress), but read config maps it to $($mappedRead.SnpxAddress)."
    }

    $writeStart = [int]$mappedRead.SnpxStart
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

$restoreValue = $null
if ($plan.restoration.required) {
    if ($plan.write.type -eq "bool") {
        $restoreState = ([string]$plan.restoration.value).ToUpperInvariant()
        if ($restoreState -eq "ON") {
            $restoreValue = 1
        } elseif ($restoreState -eq "OFF") {
            $restoreValue = 0
        } else {
            throw "Boolean SNPX restoration value must be ON or OFF. Saw '$($plan.restoration.value)'."
        }
    } else {
        $restoreValue = [int]$plan.restoration.value
    }
}

$evidence = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    executed = [bool]$Execute
    acceptedLiveWrite = [bool]$AcceptLiveWrite
    restoreAfterWrite = [bool]$RestoreAfterWrite
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
            start = [int]$writeStart
            dynamicProjection = [bool]$usesDynamicProjection
            value = $plan.write.value
            encodedValue = [int]$writeValue
            expectedEncodedWords = @($plan.write.encodedWords | ForEach-Object { Convert-ToUInt16Word -Value $_ })
        }
        restore = if ($plan.restoration.required) {
            [ordered]@{
                operation = "asg-write-r"
                fanuc = $plan.restoration.fanuc
                snpxAddress = $plan.write.snpxAddress
                start = [int]$writeStart
                dynamicProjection = [bool]$usesDynamicProjection
                value = $plan.restoration.value
                encodedValue = [int]$restoreValue
                expectedEncodedWords = @($plan.restoration.encodedWords | ForEach-Object { Convert-ToUInt16Word -Value $_ })
            }
        } else {
            $null
        }
    }
    operatorApproval = [ordered]@{
        required = [bool]$plan.operatorApproval.required
        requiredPhrase = [string]$plan.operatorApproval.requiredPhrase
        suppliedPhrase = $ApprovalPhrase
        phraseAccepted = (-not [bool]$plan.operatorApproval.required -or $ApprovalPhrase -eq [string]$plan.operatorApproval.requiredPhrase)
        warning = [string]$plan.operatorApproval.warning
    }
    restoration = [ordered]@{
        required = [bool]$plan.restoration.required
        requested = [bool]$RestoreAfterWrite
        value = $plan.restoration.value
        reason = $plan.restoration.reason
    }
    results = [ordered]@{}
}

if ($Execute) {
    if (-not $AcceptLiveWrite) {
        throw "Live SNPX write requires -AcceptLiveWrite after reviewing the approved plan."
    }
    if ([bool]$plan.operatorApproval.required -and $ApprovalPhrase -ne [string]$plan.operatorApproval.requiredPhrase) {
        throw "Live SNPX write requires exact -ApprovalPhrase: '$($plan.operatorApproval.requiredPhrase)'"
    }
    if ([bool]$plan.restoration.required -and -not $RestoreAfterWrite) {
        throw "Live SNPX write for $($plan.write.fanuc) requires -RestoreAfterWrite because the plan requires restoration to $($plan.restoration.value)."
    }

    $writeResult = Invoke-CodecToolJson -Parameters @{
        Operation = "asg-write-r"
        HostAddress = $HostAddress
        SetupFile = $setupPath
        Start = [int]$writeStart
        Value = [int]$writeValue
        AcceptLiveWrite = $true
    }

    $evidence.results.write = $writeResult
    $after = @($writeResult.after)
    Assert-EncodedWordsReadBack -Actual $after -Expected @($plan.write.encodedWords) -Context "SNPX live write for $($plan.write.fanuc)"

    if ([bool]$plan.restoration.required) {
        $restoreResult = Invoke-CodecToolJson -Parameters @{
            Operation = "asg-write-r"
            HostAddress = $HostAddress
            SetupFile = $setupPath
            Start = [int]$writeStart
            Value = [int]$restoreValue
            AcceptLiveWrite = $true
        }

        $evidence.results.restore = $restoreResult
        $restoreAfter = @($restoreResult.after)
        Assert-EncodedWordsReadBack -Actual $restoreAfter -Expected @($plan.restoration.encodedWords) -Context "SNPX live restoration for $($plan.write.fanuc)"
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
    RequiresRestoration = [bool]$plan.restoration.required
    RestoredAfterWrite = [bool]($Execute -and $plan.restoration.required -and $RestoreAfterWrite)
    SnpxAddress = $plan.write.snpxAddress
    Start = [int]$writeStart
    DynamicProjection = [bool]$usesDynamicProjection
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
}
