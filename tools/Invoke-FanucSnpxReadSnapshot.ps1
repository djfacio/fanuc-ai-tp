param(
    [string]$ConfigPath = "..\config\snpx-readonly.psd1",
    [string]$OutputPath = "generated\cell-status\snpx-values.json",
    [switch]$PlanOnly
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

$validator = Join-Path $scriptRoot "Test-FanucSnpxReadonlyConfig.ps1"
& $validator -ConfigPath $resolvedConfig -Quiet

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig
$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$values = [ordered]@{
    metadata = [ordered]@{
        generatedAt = (Get-Date).ToString("o")
        source = "snpx-plan"
        protocol = $config.Protocol
        mappingMode = $config.MappingMode
        assignmentMode = $config.AddressAssignment.Mode
        robotIp = $config.RobotIp
        port = $config.Port
        liveRead = $false
        notes = "Plan-only SNPX values file. Live reads must program and verify the private ASG projection before reading %R."
        reads = @($config.Reads | ForEach-Object {
            [ordered]@{
                fanuc = $_.Fanuc
                snapshotKey = $_.SnapshotKey
                type = $_.Type
                asgSlot = [int]$_.AsgSlot
                setAsgRegion = $_.SetAsgRegion
                setAsgDataType = $_.SetAsgDataType
                setAsgMultiply = [int]$_.SetAsgMultiply
                snpxAddress = $_.SnpxAddress
                wordCount = [int]$_.WordCount
                setAsgCommand = "SETASG $($_.SnpxStart) $($_.WordCount) $($_.SetAsgRegion) $($_.SetAsgMultiply)"
            }
        })
    }
    registers = [ordered]@{}
    ioSignals = [ordered]@{}
    programPresence = [ordered]@{}
    operatorChecks = [ordered]@{}
}

foreach ($read in @($config.Reads)) {
    if ($read.Fanuc -match '^R\[') {
        $values.registers[$read.SnapshotKey] = $null
    } elseif ($read.Fanuc -match '^(D[IO]|R[IO])\[') {
        $values.ioSignals[$read.SnapshotKey] = $null
    }
}

if (-not $PlanOnly -and [bool]$config.Enabled) {
    throw "Live SNPX reads are not implemented yet. Next step is to wire the local vendor\snpx-codec source into a project-owned live reader."
}

$values | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

[pscustomobject]@{
    Protocol = $config.Protocol
    MappingMode = $config.MappingMode
    RobotIp = $config.RobotIp
    Port = $config.Port
    ReadCount = @($config.Reads).Count
    LiveRead = $false
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
}
