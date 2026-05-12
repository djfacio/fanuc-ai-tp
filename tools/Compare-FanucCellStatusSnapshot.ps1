param(
    [Parameter(Mandatory = $true)]
    [string]$BeforePath,

    [Parameter(Mandatory = $true)]
    [string]$AfterPath,

    [string]$OutputPath
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

function ConvertTo-Map {
    param(
        [object[]]$Rows,
        [string]$KeyProperty,
        [string]$ValueProperty
    )

    $map = @{}
    foreach ($row in @($Rows)) {
        if ($null -eq $row) {
            continue
        }
        $key = [string]$row.$KeyProperty
        $map[$key] = $row.$ValueProperty
    }
    return $map
}

function Compare-Map {
    param(
        [string]$Type,
        [hashtable]$Before,
        [hashtable]$After
    )

    $keys = @($Before.Keys + $After.Keys | Sort-Object -Unique)
    foreach ($key in $keys) {
        $beforeValue = if ($Before.ContainsKey($key)) { $Before[$key] } else { $null }
        $afterValue = if ($After.ContainsKey($key)) { $After[$key] } else { $null }
        if ([string]$beforeValue -ne [string]$afterValue) {
            [pscustomobject]@{
                Type = $Type
                Name = $key
                Before = $beforeValue
                After = $afterValue
            }
        }
    }
}

$resolvedBeforePath = Resolve-ProjectPath $BeforePath
$resolvedAfterPath = Resolve-ProjectPath $AfterPath

if (-not (Test-Path -LiteralPath $resolvedBeforePath)) {
    throw "Before snapshot not found: $resolvedBeforePath"
}
if (-not (Test-Path -LiteralPath $resolvedAfterPath)) {
    throw "After snapshot not found: $resolvedAfterPath"
}

$before = Get-Content -LiteralPath $resolvedBeforePath -Raw | ConvertFrom-Json
$after = Get-Content -LiteralPath $resolvedAfterPath -Raw | ConvertFrom-Json

$changes = @()
$changes += Compare-Map -Type "register" -Before (ConvertTo-Map -Rows $before.registers -KeyProperty "address" -ValueProperty "value") -After (ConvertTo-Map -Rows $after.registers -KeyProperty "address" -ValueProperty "value")
$changes += Compare-Map -Type "ioSignal" -Before (ConvertTo-Map -Rows $before.ioSignals -KeyProperty "signal" -ValueProperty "state") -After (ConvertTo-Map -Rows $after.ioSignals -KeyProperty "signal" -ValueProperty "state")
$changes += Compare-Map -Type "programPresence" -Before (ConvertTo-Map -Rows $before.programPresence -KeyProperty "program" -ValueProperty "present") -After (ConvertTo-Map -Rows $after.programPresence -KeyProperty "program" -ValueProperty "present")
$changes += Compare-Map -Type "operatorCheck" -Before (ConvertTo-Map -Rows $before.operatorChecks -KeyProperty "name" -ValueProperty "value") -After (ConvertTo-Map -Rows $after.operatorChecks -KeyProperty "name" -ValueProperty "value")

$report = [ordered]@{
    schemaVersion = 1
    comparedAt = (Get-Date).ToString("o")
    beforePath = (Get-Item -LiteralPath $resolvedBeforePath).FullName
    afterPath = (Get-Item -LiteralPath $resolvedAfterPath).FullName
    beforeLabel = $before.label
    afterLabel = $after.label
    changeCount = @($changes).Count
    changes = @($changes)
}

if ($OutputPath) {
    $resolvedOutputPath = Resolve-ProjectPath $OutputPath
    $outputDir = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII
}

[pscustomobject]@{
    BeforeLabel = $report.beforeLabel
    AfterLabel = $report.afterLabel
    ChangeCount = $report.changeCount
    Changes = @($changes)
    OutputPath = if ($OutputPath) { (Get-Item -LiteralPath $resolvedOutputPath).FullName } else { $null }
}
