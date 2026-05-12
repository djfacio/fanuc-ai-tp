param(
    [string]$ConfigPath = "..\config\snpx-readonly.psd1",
    [string]$OutputPath = "generated\cell-status\snpx-live-read.json",
    [string]$HostAddress,
    [switch]$Execute,
    [switch]$AcceptAsgSetup
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

function ConvertFrom-SnpxWords {
    param(
        [object[]]$Words,
        [int]$WordCount
    )

    $value = [int]$Words[0]
    if ($WordCount -ge 2) {
        $value = $value -bor ([int]$Words[1] -shl 16)
    }
    return $value
}

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

$validator = Join-Path $scriptRoot "Test-FanucSnpxReadonlyConfig.ps1"
& $validator -ConfigPath $resolvedConfig -Quiet

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig
if (-not $HostAddress) {
    $HostAddress = "$($config.RobotIp):$($config.Port)"
}

$probes = @($config.SystemProbes | Sort-Object { [int]$_.SnpxStart })
$reads = @($config.Reads | Sort-Object { [int]$_.SnpxStart })
$setasgEntries = @($probes + $reads)
$setasg = @($setasgEntries | ForEach-Object {
    "SETASG $($_.SnpxStart) $($_.WordCount) $($_.SetAsgRegion) $($_.SetAsgMultiply)"
})

$minStart = ($setasgEntries | ForEach-Object { [int]$_.SnpxStart } | Measure-Object -Minimum).Minimum
$maxEnd = ($setasgEntries | ForEach-Object { [int]$_.SnpxStart + [int]$_.WordCount - 1 } | Measure-Object -Maximum).Maximum
$readCount = [int]$maxEnd - [int]$minStart + 1

$evidence = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    executed = [bool]$Execute
    hostAddress = $HostAddress
    configPath = (Get-Item -LiteralPath $resolvedConfig).FullName
    protocol = $config.Protocol
    mappingMode = $config.MappingMode
    asgSetupAccepted = [bool]$AcceptAsgSetup
    commands = [ordered]@{
        clrasg = "CLRASG"
        setasg = $setasg
        setupFile = $null
        read = [ordered]@{
            operation = "read-r"
            start = [int]$minStart
            count = $readCount
        }
    }
    results = [ordered]@{}
}

if ($Execute) {
    if (-not $AcceptAsgSetup) {
        throw "Live SNPX read setup uses CLRASG/SETASG on the private mapping. Re-run with -AcceptAsgSetup after reviewing the command list."
    }

    $setupPath = Resolve-ProjectPath "generated\cell-status\snpx-asg-commands.txt"
    $setupDir = Split-Path -Parent $setupPath
    if (-not (Test-Path -LiteralPath $setupDir)) {
        New-Item -ItemType Directory -Path $setupDir -Force | Out-Null
    }
    $setasg | Set-Content -LiteralPath $setupPath -Encoding ASCII
    $evidence.commands.setupFile = (Get-Item -LiteralPath $setupPath).FullName

    $readResult = Invoke-CodecToolJson -Parameters @{
        Operation = "asg-read"
        HostAddress = $HostAddress
        SetupFile = $setupPath
        Start = [int]$minStart
        Count = [int]$readCount
    }
    $evidence.results.read = $readResult

    $words = @($readResult.words)
    $probeValues = [ordered]@{}
    foreach ($probe in $probes) {
        $offset = [int]$probe.SnpxStart - [int]$minStart
        $rawWords = @($words[$offset..($offset + [int]$probe.WordCount - 1)])
        $probeValue = [int]$rawWords[0]
        if ([int]$probe.WordCount -ge 2) {
            $probeValue = $probeValue -bor ([int]$rawWords[1] -shl 16)
        }
        $probeValues[$probe.SetAsgRegion] = $probeValue
        if ([bool]$probe.RequireNonZero -and $probeValue -eq 0) {
            throw "SNPX ASG probe '$($probe.SetAsgRegion)' returned zero after SETASG. Treating mapping as invalid."
        }
    }
    $evidence.results.probes = $probeValues

    $values = [ordered]@{
        metadata = [ordered]@{
            generatedAt = (Get-Date).ToString("o")
            source = "snpx-live-read"
            protocol = $config.Protocol
            mappingMode = $config.MappingMode
            robotIp = $config.RobotIp
            port = $config.Port
            liveRead = $true
        }
        registers = [ordered]@{}
        ioSignals = [ordered]@{}
        programPresence = [ordered]@{}
        operatorChecks = [ordered]@{}
    }

    foreach ($read in $reads) {
        $offset = [int]$read.SnpxStart - [int]$minStart
        $rawWords = @($words[$offset..($offset + [int]$read.WordCount - 1)])
        if ($read.Type -eq "bool") {
            $value = ([int]$rawWords[0] -ne 0)
            $values.ioSignals[$read.SnapshotKey] = $value
        } else {
            $value = ConvertFrom-SnpxWords -Words $rawWords -WordCount ([int]$read.WordCount)
            if ($read.Representation -eq "scaled-word") {
                $value = [decimal]$value / [decimal]$read.ScaleDivisor
            }
            $values.registers[$read.SnapshotKey] = $value
        }
    }

    $valuesPath = Resolve-ProjectPath "generated\cell-status\snpx-live-values.json"
    $values | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $valuesPath -Encoding ASCII
    $evidence.results.valuesPath = (Get-Item -LiteralPath $valuesPath).FullName
}

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

[pscustomobject]@{
    Executed = [bool]$Execute
    HostAddress = $HostAddress
    SetAsgCount = $setasg.Count
    ReadStart = [int]$minStart
    ReadCount = $readCount
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
    ValuesPath = if ($Execute -and $evidence.results.valuesPath) { $evidence.results.valuesPath } else { $null }
}
