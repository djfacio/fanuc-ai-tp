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

$records = foreach ($file in $analysisFiles) {
    $record = Get-Content -LiteralPath $file.FullName -Raw | ConvertFrom-Json
    $summary = $record.summary
    [pscustomobject]@{
        ProgramName = $record.programName
        Status = $record.status
        LineCount = if ($summary) { [int]$summary.lineCount } else { 0 }
        MotionLineCount = if ($summary) { [int]$summary.motionLineCount } else { 0 }
        CallLineCount = if ($summary) { [int]$summary.callLineCount } else { 0 }
        RegisterReferenceCount = if ($summary) { [int]$summary.registerWriteCount } else { 0 }
        IoWriteCount = if ($summary) { [int]$summary.ioWriteCount } else { 0 }
        AnalysisPath = $file.FullName
        LsPath = $record.lsPath
        Error = $record.error
    }
}

$records = @($records | Sort-Object ProgramName)
$decoded = @($records | Where-Object { $_.Status -eq "decoded" })
$withMotion = @($decoded | Where-Object { $_.MotionLineCount -gt 0 })
$withCalls = @($decoded | Where-Object { $_.CallLineCount -gt 0 })
$withIo = @($decoded | Where-Object { $_.IoWriteCount -gt 0 })
$withRegisterRefs = @($decoded | Where-Object { $_.RegisterReferenceCount -gt 0 })

$summaryObject = [pscustomobject]@{
    AnalysisPath = $resolvedAnalysisPath.Path
    ProgramCount = $records.Count
    DecodedCount = $decoded.Count
    FailedCount = @($records | Where-Object { $_.Status -ne "decoded" }).Count
    MotionProgramCount = $withMotion.Count
    CallProgramCount = $withCalls.Count
    IoProgramCount = $withIo.Count
    RegisterReferenceProgramCount = $withRegisterRefs.Count
    TotalMotionLines = ($decoded | Measure-Object MotionLineCount -Sum).Sum
    TotalCallLines = ($decoded | Measure-Object CallLineCount -Sum).Sum
    TotalIoWrites = ($decoded | Measure-Object IoWriteCount -Sum).Sum
    TotalRegisterReferences = ($decoded | Measure-Object RegisterReferenceCount -Sum).Sum
    TopMotionPrograms = @($decoded | Sort-Object -Property @{ Expression = "MotionLineCount"; Descending = $true }, "ProgramName" | Select-Object -First 10 ProgramName, MotionLineCount, CallLineCount, IoWriteCount)
    TopCallPrograms = @($decoded | Sort-Object -Property @{ Expression = "CallLineCount"; Descending = $true }, "ProgramName" | Select-Object -First 10 ProgramName, CallLineCount, MotionLineCount, IoWriteCount)
    TopIoPrograms = @($decoded | Sort-Object -Property @{ Expression = "IoWriteCount"; Descending = $true }, "ProgramName" | Select-Object -First 10 ProgramName, IoWriteCount, MotionLineCount, CallLineCount)
    Records = $records
}

if ($WriteMarkdown) {
    $summaryPath = Join-Path $resolvedAnalysisPath.Path "summary.md"
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Production Analysis Summary")
    $lines.Add("")
    $lines.Add("Analysis path: " + $resolvedAnalysisPath.Path)
    $lines.Add("")
    $lines.Add("## Counts")
    $lines.Add("")
    $lines.Add("- Programs analyzed: $($summaryObject.ProgramCount)")
    $lines.Add("- Decoded: $($summaryObject.DecodedCount)")
    $lines.Add("- Failed: $($summaryObject.FailedCount)")
    $lines.Add("- Programs with motion: $($summaryObject.MotionProgramCount)")
    $lines.Add("- Programs with CALLs: $($summaryObject.CallProgramCount)")
    $lines.Add("- Programs with output writes: $($summaryObject.IoProgramCount)")
    $lines.Add("- Programs with register references: $($summaryObject.RegisterReferenceProgramCount)")
    $lines.Add("")
    $lines.Add("## Top Motion Programs")
    $lines.Add("")
    $lines.Add("| Program | Motion | Calls | IO writes |")
    $lines.Add("| --- | ---: | ---: | ---: |")
    foreach ($row in $summaryObject.TopMotionPrograms) {
        $lines.Add("| $($row.ProgramName) | $($row.MotionLineCount) | $($row.CallLineCount) | $($row.IoWriteCount) |")
    }
    $lines.Add("")
    $lines.Add("## Top CALL Programs")
    $lines.Add("")
    $lines.Add("| Program | Calls | Motion | IO writes |")
    $lines.Add("| --- | ---: | ---: | ---: |")
    foreach ($row in $summaryObject.TopCallPrograms) {
        $lines.Add("| $($row.ProgramName) | $($row.CallLineCount) | $($row.MotionLineCount) | $($row.IoWriteCount) |")
    }
    $lines.Add("")
    $lines.Add("## Top IO Programs")
    $lines.Add("")
    $lines.Add("| Program | IO writes | Motion | Calls |")
    $lines.Add("| --- | ---: | ---: | ---: |")
    foreach ($row in $summaryObject.TopIoPrograms) {
        $lines.Add("| $($row.ProgramName) | $($row.IoWriteCount) | $($row.MotionLineCount) | $($row.CallLineCount) |")
    }
    $lines.Add("")
    $lines.Add("## Template Signals")
    $lines.Add("")
    $lines.Add("- Programs with no motion and IO writes are good candidates for guarded IO utility templates.")
    $lines.Add("- Programs with CALL-heavy structure are good candidates for orchestration templates.")
    $lines.Add("- Programs with motion and few CALLs are good candidates for simple move/check templates after frame/tool/payload evidence exists.")
    $lines.Add("- Calculation-only programs are good candidates for read-only or register/position-register helper templates.")

    $lines | Set-Content -LiteralPath $summaryPath -Encoding ASCII
    Add-Member -InputObject $summaryObject -NotePropertyName SummaryPath -NotePropertyValue (Get-Item -LiteralPath $summaryPath).FullName
}

$summaryObject
