param(
    [string]$CatalogPath = "..\config\template-catalog.psd1",
    [string]$OutputPath = "generated\templates\template-catalog.json",
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

if ([System.IO.Path]::IsPathRooted($CatalogPath)) {
    $resolvedCatalog = Resolve-Path -LiteralPath $CatalogPath
} else {
    $resolvedCatalog = Resolve-Path -LiteralPath (Join-Path $scriptRoot $CatalogPath)
}
$resolvedCatalogPath = $resolvedCatalog.Path

$validator = Join-Path $scriptRoot "Test-FanucTemplateCatalog.ps1"
& $validator -CatalogPath $resolvedCatalogPath -Quiet

$catalog = Import-PowerShellDataFile -LiteralPath $resolvedCatalogPath
$templates = @($catalog.Templates | ForEach-Object {
    [ordered]@{
        id = $_.Id
        programName = $_.ProgramName
        specType = if ($_.SpecType) { $_.SpecType } elseif ($_.ExampleSpec -like "*.motion-application.json") { "motion-application" } else { "program" }
        templateId = $_.TemplateId
        exampleSpec = $_.ExampleSpec
        motionClass = $_.MotionClass
        purpose = $_.Purpose
        allowedOperationTypes = @($_.AllowedOperationTypes)
        registerWrites = @($_.RegisterWrites)
        ioWrites = @($_.IoWrites)
        callTargets = @($_.CallTargets)
        positionRegisters = @($_.PositionRegisters)
        evidence = @($_.Evidence)
        status = $_.Status
    }
})

$artifact = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    catalogPath = (Get-Item -LiteralPath $resolvedCatalogPath).FullName
    templateCount = $templates.Count
    templates = $templates
}

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$artifact | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

$markdownPath = $null
if ($WriteMarkdown) {
    $markdownPath = [System.IO.Path]::ChangeExtension($resolvedOutputPath, ".md")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# FANUC TP Template Catalog")
    $lines.Add("")
    $lines.Add("Generated: $($artifact.generatedAt)")
    $lines.Add("")
    $lines.Add("| Template | Program | Motion | Operations | Resources | Status |")
    $lines.Add("| --- | --- | --- | --- | --- | --- |")
    foreach ($template in $templates) {
        $operations = ($template.allowedOperationTypes -join ", ")
        $resources = @($template.registerWrites + $template.ioWrites + $template.callTargets + $template.positionRegisters)
        $resourceText = if ($resources.Count -gt 0) { $resources -join ", " } else { "none" }
        $lines.Add("| $($template.id) | $($template.programName) | $($template.motionClass) | $operations | $resourceText | $($template.status) |")
    }
    $lines.Add("")
    $lines.Add("Templates are deterministic and spec-driven. Motion templates remain gated by motion application validation, LS/spec matching, optional evidence, upload, and readback. Robot-side physical verification is operator-owned.")
    $lines | Set-Content -LiteralPath $markdownPath -Encoding ASCII
}

[pscustomobject]@{
    TemplateCount = $templates.Count
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
    MarkdownPath = if ($markdownPath) { (Get-Item -LiteralPath $markdownPath).FullName } else { $null }
}
