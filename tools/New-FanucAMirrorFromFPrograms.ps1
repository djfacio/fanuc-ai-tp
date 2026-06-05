param(
    [string]$DependencyMapPath = "generated\dependency-map\20260513-160748-F_MAIN\dependency-map.json",
    [string]$OutputRoot = "generated",
    [switch]$CleanExistingAPrograms,
    [switch]$Force
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

function Assert-UnderProject {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($projectRoot)
    if (-not $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to touch path outside project root: $fullPath"
    }

    return $fullPath
}

function Test-TextIsLocallyMotionAffecting {
    param([string]$Text)

    if ($Text -match '(?im)^\s*\d+:\s*[JLC]\s+') {
        return $true
    }

    if ($Text -match '(?im)^\s*\d+:\s*PR\[(?:GP\d+:)?[^\]]+\]\s*=') {
        return $true
    }

    if ($Text -match '(?im)^\s*\d+:\s*CALL\s+A_[A-Za-z0-9_]*\b') {
        return $true
    }

    return $false
}

function Test-TextOwnsMotionResource {
    param(
        [string]$ProgramName,
        [hashtable]$TextsByProgram,
        [System.Collections.Generic.HashSet[string]]$VisitedPrograms
    )

    $key = $ProgramName.ToUpperInvariant()
    if ($VisitedPrograms.Contains($key)) {
        return $false
    }
    [void]$VisitedPrograms.Add($key)

    if (-not $TextsByProgram.ContainsKey($key)) {
        return $false
    }

    $programText = [string]$TextsByProgram[$key]
    if ($programText -match '(?im)^\s*\d+:\s*[JLC]\s+') {
        return $true
    }

    if ($programText -match '(?im)^\s*\d+:\s*PR\[(?:GP\d+:)?[^\]]+\]\s*=') {
        return $true
    }

    $callMatches = [regex]::Matches($programText, '(?im)^\s*\d+:\s*CALL\s+(A_[A-Za-z0-9_]*)\b')
    foreach ($callMatch in $callMatches) {
        $target = $callMatch.Groups[1].Value.ToUpperInvariant()
        if (Test-TextOwnsMotionResource -ProgramName $target -TextsByProgram $TextsByProgram -VisitedPrograms $VisitedPrograms) {
            return $true
        }
    }

    return $false
}

$resolvedMapPath = Resolve-ProjectPath $DependencyMapPath
$resolvedOutputRoot = Resolve-ProjectPath $OutputRoot
$sourcesDir = Join-Path $resolvedOutputRoot "sources"
$jobsDir = Join-Path $resolvedOutputRoot "jobs"
$compiledDir = Join-Path $resolvedOutputRoot "compiled"

foreach ($path in @($resolvedMapPath, $resolvedOutputRoot)) {
    Assert-UnderProject $path | Out-Null
}

if (-not (Test-Path -LiteralPath $resolvedMapPath)) {
    throw "Dependency map not found: $resolvedMapPath"
}

foreach ($path in @($sourcesDir, $jobsDir, $compiledDir)) {
    Assert-UnderProject $path | Out-Null
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

if ($CleanExistingAPrograms) {
    foreach ($path in Get-ChildItem -LiteralPath $sourcesDir -Filter "A_*.LS" -File -ErrorAction SilentlyContinue) {
        Assert-UnderProject $path.FullName | Out-Null
        Remove-Item -LiteralPath $path.FullName -Force
    }

    foreach ($path in Get-ChildItem -LiteralPath $compiledDir -Filter "A_*.TP" -File -ErrorAction SilentlyContinue) {
        Assert-UnderProject $path.FullName | Out-Null
        Remove-Item -LiteralPath $path.FullName -Force
    }

    foreach ($path in Get-ChildItem -LiteralPath $jobsDir -Directory -Filter "A_*" -ErrorAction SilentlyContinue) {
        Assert-UnderProject $path.FullName | Out-Null
        Remove-Item -LiteralPath $path.FullName -Recurse -Force
    }
}

$dependencyMap = Get-Content -LiteralPath $resolvedMapPath -Raw | ConvertFrom-Json
$sourceRecords = @(
    $dependencyMap.requiredPrograms |
        Where-Object { $_.extension -eq ".TP" -and $_.programName -like "F_*" -and $_.status -eq "decoded" -and $_.lsPath } |
        Sort-Object programName
)

if ($sourceRecords.Count -eq 0) {
    throw "No decoded F_ TP programs found in dependency map: $resolvedMapPath"
}

$renameMap = [ordered]@{}
foreach ($record in $sourceRecords) {
    $from = [string]$record.programName
    $to = "A_" + $from.Substring(2)
    $renameMap[$from.ToUpperInvariant()] = $to.ToUpperInvariant()
}

$mapKeysLongestFirst = @($renameMap.Keys | Sort-Object Length -Descending)
$records = New-Object System.Collections.Generic.List[object]
$textsByProgram = @{}
$ascii = [System.Text.Encoding]::ASCII

foreach ($record in $sourceRecords) {
    $sourceProgram = ([string]$record.programName).ToUpperInvariant()
    $targetProgram = $renameMap[$sourceProgram]
    $sourcePath = Resolve-ProjectPath ([string]$record.lsPath)
    Assert-UnderProject $sourcePath | Out-Null

    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Decoded LS source missing for $sourceProgram`: $sourcePath"
    }

    $text = Get-Content -LiteralPath $sourcePath -Raw
    foreach ($key in $mapKeysLongestFirst) {
        $value = $renameMap[$key]
        $text = [regex]::Replace($text, "(?<![A-Z0-9_])$([regex]::Escape($key))(?![A-Z0-9_])", $value)
    }

    $text = [regex]::Replace($text, "(?im)^\s*FILE_NAME\s*=\s*[^;]*;", "FILE_NAME`t= ;")

    if (-not (Test-TextIsLocallyMotionAffecting -Text $text)) {
        $text = [regex]::Replace(
            $text,
            "(?im)^(\s*DEFAULT_GROUP\s*=\s*)[^;]+;",
            "`$1*,*,*,*,*,*,*,*;"
        )
    }
    $textsByProgram[$targetProgram] = $text

    $headerMatches = [regex]::Matches($text, "(?im)^\s*/PROG\s+$([regex]::Escape($targetProgram))(?:\s+Macro)?\s*$")
    if ($headerMatches.Count -ne 1) {
        throw "Mirrored source for $targetProgram does not contain exactly one matching /PROG header."
    }

    foreach ($key in $mapKeysLongestFirst) {
        if ($text -match "(?<![A-Z0-9_])$([regex]::Escape($key))(?![A-Z0-9_])") {
            throw "Mirrored source for $targetProgram still references mapped source program $key."
        }
    }

    $targetSourcePath = Join-Path $sourcesDir ($targetProgram + ".LS")
    $targetJobDir = Join-Path $jobsDir $targetProgram
    $targetJobSourcePath = Join-Path $targetJobDir ($targetProgram + ".LS")
    foreach ($path in @($targetSourcePath, $targetJobSourcePath)) {
        Assert-UnderProject $path | Out-Null
        if ((Test-Path -LiteralPath $path) -and -not $Force) {
            throw "Output already exists: $path. Use -Force to overwrite."
        }
    }

    if (-not (Test-Path -LiteralPath $targetJobDir)) {
        New-Item -ItemType Directory -Path $targetJobDir -Force | Out-Null
    }

    $normalizedText = ($text -replace "\r?\n", "`r`n").TrimEnd() + "`r`n"
    [System.IO.File]::WriteAllText($targetSourcePath, $normalizedText, $ascii)
    [System.IO.File]::WriteAllText($targetJobSourcePath, $normalizedText, $ascii)

    $records.Add([pscustomobject]@{
        SourceProgram = $sourceProgram
        TargetProgram = $targetProgram
        SourcePath = (Get-Item -LiteralPath $sourcePath).FullName
        TargetSourcePath = (Get-Item -LiteralPath $targetSourcePath).FullName
        JobSourcePath = (Get-Item -LiteralPath $targetJobSourcePath).FullName
        MacroMarker = [bool]$record.macroMarker
        DirectCallCount = [int]$record.directCallCount
        DirectRunCount = [int]$record.directRunCount
    })
}

foreach ($record in @($records.ToArray())) {
    $targetProgram = [string]$record.TargetProgram
    $ownsMotionResource = Test-TextOwnsMotionResource -ProgramName $targetProgram -TextsByProgram $textsByProgram -VisitedPrograms ([System.Collections.Generic.HashSet[string]]::new())
    if ($ownsMotionResource) {
        continue
    }

    foreach ($path in @([string]$record.TargetSourcePath, [string]$record.JobSourcePath)) {
        Assert-UnderProject $path | Out-Null
        $existingText = Get-Content -LiteralPath $path -Raw
        $normalizedText = [regex]::Replace(
            $existingText,
            "(?im)^(\s*DEFAULT_GROUP\s*=\s*)[^;]+;",
            "`$1*,*,*,*,*,*,*,*;"
        )
        if ($normalizedText -ne $existingText) {
            [System.IO.File]::WriteAllText($path, $normalizedText, $ascii)
        }
    }
}

$externalDependencies = @(
    $dependencyMap.requiredPrograms |
        Where-Object { -not ($_.extension -eq ".TP" -and $_.programName -like "F_*") } |
        Select-Object programName, extension, status
)

$manifestPath = Join-Path $resolvedOutputRoot "a-main-f-mirror.json"
[ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    style = "f-program-behavior-preserving-a-mirror"
    dependencyMapPath = (Get-Item -LiteralPath $resolvedMapPath).FullName
    sourceRootProgram = $dependencyMap.rootProgram
    targetRootProgram = "A_MAIN"
    programCount = $records.Count
    transformation = @(
        "Decoded F_ TP programs in the F_MAIN dependency closure are mirrored as A_ TP programs.",
        "Mapped F_ program names are replaced in /PROG headers, CALL/RUN targets, task-name string arguments, and comments.",
        "Non-mapped external dependencies such as F_TASK_STATUS.PC and K_VS_*.PC remain external dependencies.",
        "True no-motion helper programs are normalized to DEFAULT_GROUP = *,*,*,*,*,*,*,* for generated upload safety.",
        "No logic, motion, register, PR, flag, IO, timeout, frame/tool, payload, or position records are intentionally changed in this pass."
    )
    renameMap = $renameMap
    programs = @($records.ToArray())
    externalDependencies = @($externalDependencies)
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding ASCII

[pscustomobject]@{
    ProgramCount = $records.Count
    ManifestPath = (Get-Item -LiteralPath $manifestPath).FullName
    RootSource = "F_MAIN"
    RootTarget = "A_MAIN"
    Programs = @($records.ToArray())
    ExternalDependencies = @($externalDependencies)
}
