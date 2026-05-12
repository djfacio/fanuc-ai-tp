param(
    [string]$ConfigPath = "..\config\interface-strategy.psd1",
    [string]$OutputPath = "generated\interfaces\interface-strategy.json",
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
$resolvedConfigPath = $resolvedConfig.Path

$validator = Join-Path $scriptRoot "Test-FanucInterfaceStrategy.ps1"
& $validator -ConfigPath $resolvedConfigPath -Quiet

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath
$artifact = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    configPath = (Get-Item -LiteralPath $resolvedConfigPath).FullName
    interfaces = @($config.Interfaces)
    messageSchemas = @($config.MessageSchemas)
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
    $lines.Add("# FANUC Interface Strategy")
    $lines.Add("")
    $lines.Add("| Interface | Enabled | Authority | Live writes | Program run | Motion | Role |")
    $lines.Add("| --- | --- | --- | --- | --- | --- | --- |")
    foreach ($interface in @($config.Interfaces)) {
        $lines.Add("| $($interface.Name) | $($interface.Enabled) | $($interface.CommandAuthority) | $($interface.AllowsLiveWrites) | $($interface.AllowsProgramRun) | $($interface.AllowsRobotMotion) | $($interface.Role) |")
    }
    $lines.Add("")
    $lines.Add("## Proposed KAREL TCP Message Schemas")
    $lines.Add("")
    $lines.Add("| Message | Enabled | Direction | Writes | Required fields |")
    $lines.Add("| --- | --- | --- | --- | --- |")
    foreach ($schema in @($config.MessageSchemas)) {
        $fields = @($schema.RequiredFields) -join ", "
        $lines.Add("| $($schema.Name) | $($schema.Enabled) | $($schema.Direction) | $($schema.AllowsWrites) | $fields |")
    }
    $lines | Set-Content -LiteralPath $markdownPath -Encoding ASCII
}

[pscustomobject]@{
    InterfaceCount = @($config.Interfaces).Count
    MessageSchemaCount = @($config.MessageSchemas).Count
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
    MarkdownPath = if ($markdownPath) { (Get-Item -LiteralPath $markdownPath).FullName } else { $null }
}
