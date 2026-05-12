param(
    [string]$ReadConfigPath = "..\config\snpx-readonly.psd1",
    [string]$WriteConfigPath = "..\config\snpx-writes.psd1",
    [string]$OutputPath = "generated\cell-status\snpx-commissioning-matrix.json",
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

function Resolve-InputPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $scriptRoot $Path)).Path
}

function New-MatrixRow {
    param(
        [string]$Kind,
        [object]$Entry,
        [object]$WriteEntry
    )

    $start = [int]$Entry.SnpxStart
    $wordCount = [int]$Entry.WordCount
    $fanuc = if ($Kind -eq "probe") { $Entry.SetAsgRegion } else { $Entry.Fanuc }
    $writeAllowed = ($null -ne $WriteEntry)
    $restorationRequired = $false
    if ($writeAllowed -and $WriteEntry.Type -eq "bool" -and $fanuc -match '^(DO|RO)\[') {
        $states = @($WriteEntry.AllowedStates | ForEach-Object { $_.ToUpperInvariant() })
        $restorationRequired = ($states -contains "ON" -and $states -contains "OFF")
    }

    $status = if ($Kind -eq "probe") {
        "system-probe"
    } elseif ($writeAllowed -and $restorationRequired) {
        "read-write-restore-gated"
    } elseif ($writeAllowed) {
        "read-write-approval-gated"
    } elseif ([bool]$Entry.Required) {
        "read-required"
    } else {
        "read-planned"
    }

    [ordered]@{
        kind = $Kind
        name = $Entry.Name
        fanuc = $fanuc
        snapshotKey = if ($Kind -eq "probe") { "" } else { $Entry.SnapshotKey }
        type = if ($Kind -eq "probe") { "probe" } else { $Entry.Type }
        representation = if ($Kind -eq "probe") { "word" } else { $Entry.Representation }
        setAsgRegion = $Entry.SetAsgRegion
        setAsgDataType = $Entry.SetAsgDataType
        setAsgMultiply = [int]$Entry.SetAsgMultiply
        setAsgCommand = "SETASG $start $wordCount $($Entry.SetAsgRegion) $($Entry.SetAsgMultiply)"
        asgSlot = if ($Kind -eq "probe") { $null } else { [int]$Entry.AsgSlot }
        snpxArea = "%R"
        snpxStart = $start
        snpxEnd = ($start + $wordCount - 1)
        snpxAddress = $Entry.SnpxAddress
        wordCount = $wordCount
        readRequired = if ($Kind -eq "probe") { [bool]$Entry.RequireNonZero } else { [bool]$Entry.Required }
        writeAllowed = $writeAllowed
        writeType = if ($writeAllowed) { $WriteEntry.Type } else { "" }
        requiresLiveProof = if ($writeAllowed) { [bool]$WriteEntry.RequiresLiveProof } else { $false }
        restorationRequired = $restorationRequired
        commissioningStatus = $status
    }
}

$resolvedReadConfigPath = Resolve-InputPath -Path $ReadConfigPath
$resolvedWriteConfigPath = Resolve-InputPath -Path $WriteConfigPath

$readValidator = Join-Path $scriptRoot "Test-FanucSnpxReadonlyConfig.ps1"
$writeValidator = Join-Path $scriptRoot "Test-FanucSnpxWriteConfig.ps1"
& $readValidator -ConfigPath $resolvedReadConfigPath -Quiet
& $writeValidator -ConfigPath $resolvedWriteConfigPath -Quiet

$readConfig = Import-PowerShellDataFile -LiteralPath $resolvedReadConfigPath
$writeConfig = Import-PowerShellDataFile -LiteralPath $resolvedWriteConfigPath

$writeLookup = @{}
foreach ($write in @($writeConfig.AllowedWrites)) {
    if ($write.Fanuc) {
        $writeLookup[$write.Fanuc.ToUpperInvariant()] = $write
    }
}

$rows = New-Object System.Collections.Generic.List[object]
foreach ($probe in @($readConfig.SystemProbes | Sort-Object { [int]$_.SnpxStart })) {
    $rows.Add((New-MatrixRow -Kind "probe" -Entry $probe -WriteEntry $null))
}
foreach ($read in @($readConfig.Reads | Sort-Object { [int]$_.SnpxStart })) {
    $key = $read.Fanuc.ToUpperInvariant()
    $writeEntry = if ($writeLookup.ContainsKey($key)) { $writeLookup[$key] } else { $null }
    $rows.Add((New-MatrixRow -Kind "read" -Entry $read -WriteEntry $writeEntry))
}

$collisions = New-Object System.Collections.Generic.List[object]
$rowArray = @($rows.ToArray())
for ($i = 0; $i -lt $rowArray.Count; $i++) {
    for ($j = $i + 1; $j -lt $rowArray.Count; $j++) {
        $a = $rowArray[$i]
        $b = $rowArray[$j]
        if ($a.snpxArea -eq $b.snpxArea -and [int]$a.snpxStart -le [int]$b.snpxEnd -and [int]$b.snpxStart -le [int]$a.snpxEnd) {
            $collisions.Add([ordered]@{
                left = $a.fanuc
                leftRange = "$($a.snpxAddress)..%R$('{0:d5}' -f [int]$a.snpxEnd)"
                right = $b.fanuc
                rightRange = "$($b.snpxAddress)..%R$('{0:d5}' -f [int]$b.snpxEnd)"
            })
        }
    }
}

$matrix = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    protocol = $readConfig.Protocol
    mappingMode = $readConfig.MappingMode
    assignmentMode = $readConfig.AddressAssignment.Mode
    robotIp = $readConfig.RobotIp
    port = [int]$readConfig.Port
    readConfigPath = (Get-Item -LiteralPath $resolvedReadConfigPath).FullName
    writeConfigPath = (Get-Item -LiteralPath $resolvedWriteConfigPath).FullName
    collisionRules = @(
        "Every SNPX projection row owns an inclusive %R word range.",
        "Ranges must not overlap, including system probes.",
        "Write targets must match the read projection address and word count.",
        "Output writes that request ON must restore to OFF with post-restore evidence."
    )
    rows = $rowArray
    collisions = @($collisions.ToArray())
    summary = [ordered]@{
        rowCount = $rowArray.Count
        probeCount = @($rowArray | Where-Object { $_.kind -eq "probe" }).Count
        readCount = @($rowArray | Where-Object { $_.kind -eq "read" }).Count
        writeAllowedCount = @($rowArray | Where-Object { $_.writeAllowed }).Count
        restorationRequiredCount = @($rowArray | Where-Object { $_.restorationRequired }).Count
        collisionCount = $collisions.Count
    }
}

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$matrix | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

$markdownPath = $null
if ($WriteMarkdown) {
    $markdownPath = [System.IO.Path]::ChangeExtension($resolvedOutputPath, ".md")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# SNPX Commissioning Matrix")
    $lines.Add("")
    $lines.Add("- Protocol: $($matrix.protocol)")
    $lines.Add("- Mapping mode: $($matrix.mappingMode)")
    $lines.Add("- Assignment mode: $($matrix.assignmentMode)")
    $lines.Add("- Endpoint: $($matrix.robotIp):$($matrix.port)")
    $lines.Add("- Collisions: $($matrix.summary.collisionCount)")
    $lines.Add("")
    $lines.Add("## Collision Rules")
    $lines.Add("")
    foreach ($rule in $matrix.collisionRules) {
        $lines.Add("- $rule")
    }
    $lines.Add("")
    $lines.Add("## Rows")
    $lines.Add("")
    $lines.Add("| Kind | FANUC / region | SNPX range | Words | Type | Write | Restore | Status | Name |")
    $lines.Add("| --- | --- | --- | --- | --- | --- | --- | --- | --- |")
    foreach ($row in $rowArray) {
        $range = "$($row.snpxAddress)..%R$('{0:d5}' -f [int]$row.snpxEnd)"
        $write = if ($row.writeAllowed) { "yes" } else { "no" }
        $restore = if ($row.restorationRequired) { "yes" } else { "no" }
        $lines.Add("| $($row.kind) | $($row.fanuc) | $range | $($row.wordCount) | $($row.type) / $($row.representation) | $write | $restore | $($row.commissioningStatus) | $($row.name) |")
    }
    $lines.Add("")
    if ($collisions.Count -gt 0) {
        $lines.Add("## Collisions")
        $lines.Add("")
        foreach ($collision in @($collisions)) {
            $lines.Add("- $($collision.left) $($collision.leftRange) overlaps $($collision.right) $($collision.rightRange)")
        }
    }
    $lines | Set-Content -LiteralPath $markdownPath -Encoding ASCII
}

[pscustomobject]@{
    Protocol = $matrix.protocol
    MappingMode = $matrix.mappingMode
    RowCount = $matrix.summary.rowCount
    WriteAllowedCount = $matrix.summary.writeAllowedCount
    RestorationRequiredCount = $matrix.summary.restorationRequiredCount
    CollisionCount = $matrix.summary.collisionCount
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
    MarkdownPath = if ($markdownPath) { (Get-Item -LiteralPath $markdownPath).FullName } else { $null }
}
