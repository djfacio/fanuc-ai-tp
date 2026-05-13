param(
    [string]$InventoryPath = "..\config\controller-inventory.sample.psd1",
    [string]$OutputPath = "generated\health\latest\health-check.json",
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

function Invoke-HealthStep {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    try {
        $result = & $Command
        return [ordered]@{
            name = $Name
            passed = $true
            message = ""
            result = $result
        }
    } catch {
        return [ordered]@{
            name = $Name
            passed = $false
            message = $_.Exception.Message
            result = $null
        }
    }
}

$resolvedOutputPath = Resolve-ProjectPath $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$resolvedInventoryPath = Resolve-InputPath -Path $InventoryPath
$matrixPath = Join-Path $outputDir "snpx-commissioning-matrix.json"
$catalogPath = Join-Path $outputDir "template-catalog.json"
$interfacePath = Join-Path $outputDir "interface-strategy.json"

$steps = New-Object System.Collections.Generic.List[object]
$steps.Add((Invoke-HealthStep -Name "CellMap" -Command {
    & (Join-Path $scriptRoot "Test-FanucCellMap.ps1") -Quiet
}))
$steps.Add((Invoke-HealthStep -Name "CellMapSample" -Command {
    & (Join-Path $scriptRoot "Test-FanucCellMap.ps1") -CellMapPath (Join-Path $projectRoot "config\cell-map.sample.psd1") -Quiet
}))
$steps.Add((Invoke-HealthStep -Name "CellObservations" -Command {
    & (Join-Path $scriptRoot "Test-FanucCellObservations.ps1") -Quiet
}))
$steps.Add((Invoke-HealthStep -Name "ControllerInventory" -Command {
    & (Join-Path $scriptRoot "Test-FanucControllerInventory.ps1") -InventoryPath $resolvedInventoryPath -Quiet
}))
$steps.Add((Invoke-HealthStep -Name "TemplateCatalog" -Command {
    & (Join-Path $scriptRoot "Test-FanucTemplateCatalog.ps1") -Quiet
}))
$steps.Add((Invoke-HealthStep -Name "RoboguideEvidenceConfig" -Command {
    & (Join-Path $scriptRoot "Test-FanucRoboguideEvidenceConfig.ps1") -Quiet
}))
$steps.Add((Invoke-HealthStep -Name "InterfaceStrategy" -Command {
    & (Join-Path $scriptRoot "Test-FanucInterfaceStrategy.ps1") -Quiet
}))
$steps.Add((Invoke-HealthStep -Name "SnpxReadonlyConfig" -Command {
    & (Join-Path $scriptRoot "Test-FanucSnpxReadonlyConfig.ps1") -Quiet
}))
$steps.Add((Invoke-HealthStep -Name "SnpxWriteConfig" -Command {
    & (Join-Path $scriptRoot "Test-FanucSnpxWriteConfig.ps1") -Quiet
}))

$capabilityStep = Invoke-HealthStep -Name "ControllerCapability" -Command {
    & (Join-Path $scriptRoot "Get-FanucControllerCapability.ps1") -InventoryPath $resolvedInventoryPath
}
$steps.Add($capabilityStep)

$matrixStep = Invoke-HealthStep -Name "SnpxCommissioningMatrix" -Command {
    & (Join-Path $scriptRoot "Get-FanucSnpxCommissioningMatrix.ps1") -OutputPath $matrixPath -WriteMarkdown
}
$steps.Add($matrixStep)

$catalogStep = Invoke-HealthStep -Name "TemplateCatalogArtifact" -Command {
    & (Join-Path $scriptRoot "Get-FanucTemplateCatalog.ps1") -OutputPath $catalogPath -WriteMarkdown
}
$steps.Add($catalogStep)

$interfaceStep = Invoke-HealthStep -Name "InterfaceStrategyArtifact" -Command {
    & (Join-Path $scriptRoot "Get-FanucInterfaceStrategy.ps1") -OutputPath $interfacePath -WriteMarkdown
}
$steps.Add($interfaceStep)

$stepArray = @($steps.ToArray())
$failed = @($stepArray | Where-Object { -not $_.passed })
$capability = $capabilityStep.result

$health = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    liveRobotCommandsExecuted = $false
    controllerWritesExecuted = $false
    inventoryPath = (Get-Item -LiteralPath $resolvedInventoryPath).FullName
    overallPassed = ($failed.Count -eq 0)
    summary = [ordered]@{
        stepCount = $stepArray.Count
        passedCount = @($stepArray | Where-Object { $_.passed }).Count
        failedCount = $failed.Count
        canCompileTp = if ($capability) { [bool]$capability.CanCompileTp } else { $false }
        canUploadTp = if ($capability) { [bool]$capability.CanUploadTp } else { $false }
        canReadTp = if ($capability) { [bool]$capability.CanReadTp } else { $false }
        canUseSnpx = if ($capability) { [bool]$capability.CanUseSnpx } else { $false }
        canWriteSnpx = if ($capability) { [bool]$capability.CanWriteSnpx } else { $false }
        canUseKarelBridge = if ($capability) { [bool]$capability.CanUseKarelBridge } else { $false }
        canRunRoboguideEvidence = if ($capability) { [bool]$capability.CanRunRoboguideEvidence } else { $false }
    }
    steps = $stepArray
    artifacts = [ordered]@{
        snpxCommissioningMatrix = if (Test-Path -LiteralPath $matrixPath) { (Get-Item -LiteralPath $matrixPath).FullName } else { $null }
        templateCatalog = if (Test-Path -LiteralPath $catalogPath) { (Get-Item -LiteralPath $catalogPath).FullName } else { $null }
        interfaceStrategy = if (Test-Path -LiteralPath $interfacePath) { (Get-Item -LiteralPath $interfacePath).FullName } else { $null }
    }
}

$health | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

$markdownPath = $null
if ($WriteMarkdown) {
    $markdownPath = [System.IO.Path]::ChangeExtension($resolvedOutputPath, ".md")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# FANUC Project Health Check")
    $lines.Add("")
    $lines.Add("- Generated: $($health.generatedAt)")
    $lines.Add("- Overall passed: $($health.overallPassed)")
    $lines.Add("- Live robot commands executed: false")
    $lines.Add("- Controller writes executed: false")
    $lines.Add("")
    $lines.Add("## Capabilities")
    $lines.Add("")
    $lines.Add("| Capability | Available |")
    $lines.Add("| --- | --- |")
    foreach ($name in @("canCompileTp", "canUploadTp", "canReadTp", "canUseSnpx", "canWriteSnpx", "canUseKarelBridge", "canRunRoboguideEvidence")) {
        $lines.Add("| $name | $($health.summary[$name]) |")
    }
    $lines.Add("")
    $lines.Add("## Steps")
    $lines.Add("")
    $lines.Add("| Step | Passed | Message |")
    $lines.Add("| --- | --- | --- |")
    foreach ($step in $stepArray) {
        $message = ([string]$step.message).Replace("|", "\|")
        $lines.Add("| $($step.name) | $($step.passed) | $message |")
    }
    $lines | Set-Content -LiteralPath $markdownPath -Encoding ASCII
}

[pscustomobject]@{
    OverallPassed = [bool]$health.overallPassed
    StepCount = [int]$health.summary.stepCount
    FailedCount = [int]$health.summary.failedCount
    LiveRobotCommandsExecuted = $false
    ControllerWritesExecuted = $false
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
    MarkdownPath = if ($markdownPath) { (Get-Item -LiteralPath $markdownPath).FullName } else { $null }
}

if (-not $health.overallPassed) {
    $messages = $failed | ForEach-Object { "- $($_.name): $($_.message)" }
    throw "Project health check failed:`n$($messages -join "`n")"
}
