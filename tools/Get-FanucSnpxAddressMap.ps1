param(
    [string]$ConfigPath = "..\config\snpx-readonly.psd1",
    [string]$OutputPath = "generated\cell-status\snpx-address-map.json",
    [switch]$WriteMarkdown
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
$probeRows = @($config.SystemProbes | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        Fanuc = $_.SetAsgRegion
        SnapshotKey = ""
        Type = "probe"
        Representation = "word"
        AsgSlot = 0
        SetAsgRegion = $_.SetAsgRegion
        SetAsgDataType = $_.SetAsgDataType
        SetAsgMultiply = [int]$_.SetAsgMultiply
        SetAsgCommand = "SETASG $($_.SnpxStart) $($_.WordCount) $($_.SetAsgRegion) $($_.SetAsgMultiply)"
        SnpxArea = "%R"
        SnpxStart = [int]$_.SnpxStart
        SnpxAddress = $_.SnpxAddress
        WordCount = [int]$_.WordCount
        Required = [bool]$_.RequireNonZero
    }
})

$rows = @($config.Reads | ForEach-Object {
    [pscustomobject]@{
        Name = $_.Name
        Fanuc = $_.Fanuc
        SnapshotKey = $_.SnapshotKey
        Type = $_.Type
        Representation = $_.Representation
        AsgSlot = [int]$_.AsgSlot
        SetAsgRegion = $_.SetAsgRegion
        SetAsgDataType = $_.SetAsgDataType
        SetAsgMultiply = [int]$_.SetAsgMultiply
        SetAsgCommand = "SETASG $($_.SnpxStart) $($_.WordCount) $($_.SetAsgRegion) $($_.SetAsgMultiply)"
        SnpxArea = $_.SnpxArea
        SnpxStart = [int]$_.SnpxStart
        SnpxAddress = $_.SnpxAddress
        WordCount = [int]$_.WordCount
        Required = [bool]$_.Required
    }
})
$allRows = @($probeRows + $rows)

$map = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    protocol = $config.Protocol
    mappingMode = $config.MappingMode
    robotIp = $config.RobotIp
    port = $config.Port
    enabled = [bool]$config.Enabled
    addressAssignment = $config.AddressAssignment
    probes = $probeRows
    reads = $rows
}

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$map | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

$markdownPath = $null
if ($WriteMarkdown) {
    $markdownPath = [System.IO.Path]::ChangeExtension($resolvedOutputPath, ".md")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# SNPX Address Map")
    $lines.Add("")
    $lines.Add("- Protocol: $($config.Protocol)")
    $lines.Add("- Mapping mode: $($config.MappingMode)")
    $lines.Add("- Assignment mode: $($config.AddressAssignment.Mode)")
    $lines.Add("- Robot: $($config.RobotIp):$($config.Port)")
    $lines.Add("- Enabled: $([bool]$config.Enabled)")
    $lines.Add("")
    $lines.Add("| ASG order | FANUC region | SNPX projection | Words | SETASG command | Type | Snapshot key | Required | Name |")
    $lines.Add("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    foreach ($row in $allRows) {
        $order = if ($row.Type -eq "probe") { "probe" } else { [string]$row.AsgSlot }
        $commandText = $row.SetAsgCommand
        $lines.Add("| $order | $($row.SetAsgRegion) | $($row.SnpxAddress) | $($row.WordCount) | ``$commandText`` | $($row.Type) / $($row.Representation) | $($row.SnapshotKey) | $($row.Required) | $($row.Name) |")
    }
    $lines.Add("")
    $lines.Add("These are project-owned SNPX V2 per-connection ASG assignments. Live code must run CLRASG, SETASG each row, then read back the ASG table before trusting values.")
    $lines | Set-Content -LiteralPath $markdownPath -Encoding ASCII
}

[pscustomobject]@{
    Protocol = $config.Protocol
    MappingMode = $config.MappingMode
    RobotIp = $config.RobotIp
    Port = $config.Port
    Enabled = [bool]$config.Enabled
    ReadCount = $rows.Count
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
    MarkdownPath = if ($markdownPath) { (Get-Item -LiteralPath $markdownPath).FullName } else { $null }
}
