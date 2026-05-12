param(
    [string]$AnalysisPath,
    [string]$AnalysisRoot = "generated\production-analysis",
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

function Add-Use {
    param(
        [hashtable]$Table,
        [string]$Key,
        [string]$ProgramName
    )

    if (-not $Table.ContainsKey($Key)) {
        $Table[$Key] = New-Object System.Collections.Generic.List[string]
    }
    if (-not $Table[$Key].Contains($ProgramName)) {
        $Table[$Key].Add($ProgramName)
    }
}

if (-not $AnalysisPath) {
    $resolvedAnalysisRoot = Resolve-ProjectPath $AnalysisRoot
    $latest = Get-ChildItem -LiteralPath $resolvedAnalysisRoot -Directory |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if (-not $latest) {
        throw "No production analysis runs found under $resolvedAnalysisRoot"
    }
    $AnalysisPath = $latest.FullName
}

$resolvedAnalysisPath = Resolve-Path -LiteralPath (Resolve-ProjectPath $AnalysisPath)
$analysisFiles = Get-ChildItem -LiteralPath $resolvedAnalysisPath -Recurse -Filter "analysis.json"
if ($analysisFiles.Count -eq 0) {
    throw "No analysis.json files found under $resolvedAnalysisPath"
}

$calls = @{}
$ioWrites = @{}
$registerRefs = @{}

foreach ($file in $analysisFiles) {
    $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    if ($record.status -ne "decoded" -or -not $record.lsPath -or -not (Test-Path -LiteralPath $record.lsPath)) {
        continue
    }

    $program = $record.programName
    $text = Get-Content -LiteralPath $record.lsPath -Raw
    $mnMatch = [regex]::Match($text, '(?is)/MN\s*(.*?)\s*/POS')
    if (-not $mnMatch.Success) {
        continue
    }

    foreach ($line in ($mnMatch.Groups[1].Value -split '\r?\n')) {
        foreach ($match in [regex]::Matches($line, '(?i)\bCALL\s+([A-Z][A-Z0-9_]{0,31})')) {
            Add-Use -Table $calls -Key $match.Groups[1].Value.ToUpperInvariant() -ProgramName $program
        }
        foreach ($match in [regex]::Matches($line, '(?i)\b(DO|RO)\[(\d+)(?:\s*:[^\]]*)?\]\s*=\s*(ON|OFF)')) {
            $signal = ("{0}[{1}]={2}" -f $match.Groups[1].Value.ToUpperInvariant(), $match.Groups[2].Value, $match.Groups[3].Value.ToUpperInvariant())
            Add-Use -Table $ioWrites -Key $signal -ProgramName $program
        }
        foreach ($match in [regex]::Matches($line, '(?i)\bR\[(\d+)(?:\s*:[^\]]*)?\]')) {
            $register = "R[{0}]" -f $match.Groups[1].Value
            Add-Use -Table $registerRefs -Key $register -ProgramName $program
        }
    }
}

function Convert-Table {
    param([hashtable]$Table)

    @($Table.Keys | Sort-Object | ForEach-Object {
        [pscustomobject]@{
            Resource = $_
            ProgramCount = $Table[$_].Count
            Programs = @($Table[$_] | Sort-Object)
        }
    })
}

$report = [pscustomobject]@{
    AnalysisPath = $resolvedAnalysisPath.Path
    CallTargets = Convert-Table $calls
    IoWrites = Convert-Table $ioWrites
    RegisterReferences = Convert-Table $registerRefs
}

if ($WriteMarkdown) {
    $reportPath = Join-Path $resolvedAnalysisPath.Path "resource-report.md"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Production Resource Report")
    $lines.Add("")
    $lines.Add("Analysis path: " + $resolvedAnalysisPath.Path)
    $lines.Add("")
    $lines.Add("## CALL Targets")
    $lines.Add("")
    $lines.Add("| Target | Program count | Programs |")
    $lines.Add("| --- | ---: | --- |")
    foreach ($row in $report.CallTargets) {
        $lines.Add("| $($row.Resource) | $($row.ProgramCount) | $(@($row.Programs) -join ', ') |")
    }
    $lines.Add("")
    $lines.Add("## IO Writes")
    $lines.Add("")
    $lines.Add("| Signal/state | Program count | Programs |")
    $lines.Add("| --- | ---: | --- |")
    foreach ($row in $report.IoWrites) {
        $lines.Add("| $($row.Resource) | $($row.ProgramCount) | $(@($row.Programs) -join ', ') |")
    }
    $lines.Add("")
    $lines.Add("## Register References")
    $lines.Add("")
    $lines.Add("| Register | Program count | Programs |")
    $lines.Add("| --- | ---: | --- |")
    foreach ($row in $report.RegisterReferences) {
        $lines.Add("| $($row.Resource) | $($row.ProgramCount) | $(@($row.Programs) -join ', ') |")
    }

    $lines | Set-Content -LiteralPath $reportPath -Encoding ASCII
    Add-Member -InputObject $report -NotePropertyName ReportPath -NotePropertyValue (Get-Item -LiteralPath $reportPath).FullName
}

$report
