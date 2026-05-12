param(
    [string]$InventoryPath = "..\config\controller-inventory.sample.psd1"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([System.IO.Path]::IsPathRooted($InventoryPath)) {
    $resolvedInventory = Resolve-Path -LiteralPath $InventoryPath
} elseif (Test-Path -LiteralPath $InventoryPath) {
    $resolvedInventory = Resolve-Path -LiteralPath $InventoryPath
} else {
    $resolvedInventory = Resolve-Path -LiteralPath (Join-Path $scriptRoot $InventoryPath)
}
$resolvedInventoryPath = $resolvedInventory.Path

$validator = Join-Path $scriptRoot "Test-FanucControllerInventory.ps1"
& $validator -InventoryPath $resolvedInventoryPath -Quiet

$inventory = Import-PowerShellDataFile -LiteralPath $resolvedInventoryPath
$policy = $inventory.WorkflowPolicy
$connectivity = $inventory.Connectivity
$tools = $inventory.LocalTools

$canCompileTp = [bool]($policy.AllowCompileTp -and $tools.WinOlpc.Available -and [string]$tools.WinOlpc.MakeTpPath)
$canUploadTp = [bool]($policy.AllowFtpUpload -and $connectivity.Ftp.Enabled)
$canReadTp = [bool]($policy.AllowTpReadback -and $connectivity.Ftp.Enabled)
$canUseSnpx = [bool]($policy.AllowSnpxRead -and $connectivity.Snpx.Enabled)
$canWriteSnpx = [bool]($policy.AllowSnpxWrite -and $connectivity.Snpx.Enabled)
$canUseKarelBridge = [bool]($policy.AllowKarelBridge -and $connectivity.KarelTcp.Enabled)
$canRunRoboguideEvidence = [bool]($policy.AllowRoboguideEvidence -and $tools.RoboGuide.Available -and [string]$tools.RoboGuide.WorkcellRobotPath)

[pscustomobject]@{
    InventoryPath = (Get-Item -LiteralPath $resolvedInventoryPath).FullName
    InventoryName = $inventory.InventoryName
    ControllerFamily = $inventory.Controller.Family
    SoftwareVersion = $inventory.Controller.SoftwareVersion
    CanCompileTp = $canCompileTp
    CanUploadTp = $canUploadTp
    CanReadTp = $canReadTp
    CanUseSnpx = $canUseSnpx
    CanWriteSnpx = $canWriteSnpx
    CanUseKarelBridge = $canUseKarelBridge
    CanRunRoboguideEvidence = $canRunRoboguideEvidence
    RequiresHumanApproval = [bool]$policy.RequiresHumanApproval
    FtpHost = $connectivity.Ftp.Host
    SnpxEndpoint = if ($connectivity.Snpx.Enabled) { "$($connectivity.Snpx.Host):$($connectivity.Snpx.Port)" } else { "" }
}
