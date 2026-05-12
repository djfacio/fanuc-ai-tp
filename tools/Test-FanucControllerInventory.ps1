param(
    [string]$InventoryPath = "..\config\controller-inventory.sample.psd1",
    [switch]$Quiet
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

$inventory = Import-PowerShellDataFile -LiteralPath $resolvedInventoryPath
$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param(
        [string]$Rule,
        [string]$Message
    )

    $findings.Add([pscustomobject]@{
        Rule = $Rule
        Message = $Message
    })
}

function Test-RequiredKey {
    param(
        [hashtable]$Table,
        [string]$Key,
        [string]$Path
    )

    if ($null -eq $Table -or -not $Table.ContainsKey($Key) -or $null -eq $Table[$Key]) {
        Add-Finding -Rule "RequiredFieldMissing" -Message "$Path.$Key is required."
        return $false
    }

    return $true
}

function Test-RequiredString {
    param(
        [hashtable]$Table,
        [string]$Key,
        [string]$Path
    )

    if (-not (Test-RequiredKey -Table $Table -Key $Key -Path $Path)) {
        return
    }

    if (-not [string]$Table[$Key]) {
        Add-Finding -Rule "RequiredFieldEmpty" -Message "$Path.$Key must not be empty."
    }
}

function Test-RequiredBool {
    param(
        [hashtable]$Table,
        [string]$Key,
        [string]$Path
    )

    if (-not (Test-RequiredKey -Table $Table -Key $Key -Path $Path)) {
        return
    }

    if ($Table[$Key] -isnot [bool]) {
        Add-Finding -Rule "RequiredFieldType" -Message "$Path.$Key must be true or false."
    }
}

function Test-Port {
    param(
        [object]$Value,
        [string]$Path,
        [bool]$AllowNull = $false
    )

    if ($AllowNull -and $null -eq $Value) {
        return
    }

    if ($null -eq $Value -or [int]$Value -lt 1 -or [int]$Value -gt 65535) {
        Add-Finding -Rule "PortInvalid" -Message "$Path must be between 1 and 65535."
    }
}

if ($null -eq $inventory.SchemaVersion -or [int]$inventory.SchemaVersion -ne 1) {
    Add-Finding -Rule "SchemaVersionInvalid" -Message "SchemaVersion must be 1."
}

Test-RequiredString -Table $inventory -Key "InventoryName" -Path "Inventory"

$controller = $inventory.Controller
if ($null -eq $controller) {
    Add-Finding -Rule "SectionMissing" -Message "Controller section is required."
} else {
    Test-RequiredString -Table $controller -Key "Manufacturer" -Path "Controller"
    Test-RequiredString -Table $controller -Key "Family" -Path "Controller"
    Test-RequiredString -Table $controller -Key "SoftwareVersion" -Path "Controller"
    foreach ($key in @("HasAsciiUpload", "HasKarel", "HasPcdk", "HasSnpx")) {
        Test-RequiredBool -Table $controller -Key $key -Path "Controller"
    }
}

$connectivity = $inventory.Connectivity
if ($null -eq $connectivity) {
    Add-Finding -Rule "SectionMissing" -Message "Connectivity section is required."
} else {
    $ftp = $connectivity.Ftp
    if ($null -eq $ftp) {
        Add-Finding -Rule "SectionMissing" -Message "Connectivity.Ftp section is required."
    } else {
        Test-RequiredBool -Table $ftp -Key "Enabled" -Path "Connectivity.Ftp"
        Test-RequiredString -Table $ftp -Key "Host" -Path "Connectivity.Ftp"
        Test-Port -Value $ftp.Port -Path "Connectivity.Ftp.Port"
    }

    $snpx = $connectivity.Snpx
    if ($null -eq $snpx) {
        Add-Finding -Rule "SectionMissing" -Message "Connectivity.Snpx section is required."
    } else {
        Test-RequiredBool -Table $snpx -Key "Enabled" -Path "Connectivity.Snpx"
        Test-RequiredString -Table $snpx -Key "Host" -Path "Connectivity.Snpx"
        Test-RequiredString -Table $snpx -Key "Protocol" -Path "Connectivity.Snpx"
        if ($snpx.Protocol -and $snpx.Protocol -ne "SNPX_V2") {
            Add-Finding -Rule "ProtocolInvalid" -Message "Connectivity.Snpx.Protocol must be SNPX_V2."
        }
        Test-Port -Value $snpx.Port -Path "Connectivity.Snpx.Port"
        Test-RequiredString -Table $snpx -Key "MappingMode" -Path "Connectivity.Snpx"
        if ($snpx.MappingMode -and $snpx.MappingMode -ne "per-connection") {
            Add-Finding -Rule "MappingModeInvalid" -Message "Connectivity.Snpx.MappingMode must be per-connection."
        }
    }

    $karelTcp = $connectivity.KarelTcp
    if ($null -ne $karelTcp) {
        Test-RequiredBool -Table $karelTcp -Key "Enabled" -Path "Connectivity.KarelTcp"
        Test-Port -Value $karelTcp.Port -Path "Connectivity.KarelTcp.Port" -AllowNull $true
    }
}

$localTools = $inventory.LocalTools
if ($null -eq $localTools) {
    Add-Finding -Rule "SectionMissing" -Message "LocalTools section is required."
} else {
    $winOlpc = $localTools.WinOlpc
    if ($null -eq $winOlpc) {
        Add-Finding -Rule "SectionMissing" -Message "LocalTools.WinOlpc section is required."
    } else {
        Test-RequiredBool -Table $winOlpc -Key "Available" -Path "LocalTools.WinOlpc"
        Test-RequiredKey -Table $winOlpc -Key "MakeTpPath" -Path "LocalTools.WinOlpc" | Out-Null
    }

    $roboGuide = $localTools.RoboGuide
    if ($null -eq $roboGuide) {
        Add-Finding -Rule "SectionMissing" -Message "LocalTools.RoboGuide section is required."
    } else {
        Test-RequiredBool -Table $roboGuide -Key "Available" -Path "LocalTools.RoboGuide"
        Test-RequiredKey -Table $roboGuide -Key "WorkcellRobotPath" -Path "LocalTools.RoboGuide" | Out-Null
    }
}

$policy = $inventory.WorkflowPolicy
if ($null -eq $policy) {
    Add-Finding -Rule "SectionMissing" -Message "WorkflowPolicy section is required."
} else {
    foreach ($key in @(
        "AllowCompileTp",
        "AllowFtpUpload",
        "AllowTpReadback",
        "AllowSnpxRead",
        "AllowSnpxWrite",
        "AllowKarelBridge",
        "AllowRoboguideEvidence",
        "RequiresHumanApproval"
    )) {
        Test-RequiredBool -Table $policy -Key $key -Path "WorkflowPolicy"
    }

    if ($policy.AllowFtpUpload -and -not $connectivity.Ftp.Enabled) {
        Add-Finding -Rule "PolicyUnsupported" -Message "WorkflowPolicy.AllowFtpUpload requires Connectivity.Ftp.Enabled."
    }
    if ($policy.AllowTpReadback -and -not $connectivity.Ftp.Enabled) {
        Add-Finding -Rule "PolicyUnsupported" -Message "WorkflowPolicy.AllowTpReadback requires Connectivity.Ftp.Enabled."
    }
    if ($policy.AllowSnpxRead -and -not $connectivity.Snpx.Enabled) {
        Add-Finding -Rule "PolicyUnsupported" -Message "WorkflowPolicy.AllowSnpxRead requires Connectivity.Snpx.Enabled."
    }
    if ($policy.AllowSnpxWrite -and -not $connectivity.Snpx.Enabled) {
        Add-Finding -Rule "PolicyUnsupported" -Message "WorkflowPolicy.AllowSnpxWrite requires Connectivity.Snpx.Enabled."
    }
    if ($policy.AllowKarelBridge -and ($null -eq $connectivity.KarelTcp -or -not $connectivity.KarelTcp.Enabled)) {
        Add-Finding -Rule "PolicyUnsupported" -Message "WorkflowPolicy.AllowKarelBridge requires Connectivity.KarelTcp.Enabled."
    }
    if ($policy.AllowCompileTp -and (-not $localTools.WinOlpc.Available -or -not [string]$localTools.WinOlpc.MakeTpPath)) {
        Add-Finding -Rule "PolicyUnsupported" -Message "WorkflowPolicy.AllowCompileTp requires LocalTools.WinOlpc.Available and MakeTpPath."
    }
    if ($policy.AllowRoboguideEvidence -and (-not $localTools.RoboGuide.Available -or -not [string]$localTools.RoboGuide.WorkcellRobotPath)) {
        Add-Finding -Rule "PolicyUnsupported" -Message "WorkflowPolicy.AllowRoboguideEvidence requires LocalTools.RoboGuide.Available and WorkcellRobotPath."
    }
    if (-not $policy.RequiresHumanApproval) {
        Add-Finding -Rule "HumanApprovalRequired" -Message "WorkflowPolicy.RequiresHumanApproval must remain true."
    }
}

$result = New-Object psobject -Property ([ordered]@{
    Path = (Get-Item -LiteralPath $resolvedInventoryPath).FullName
    IsValid = ($findings.Count -eq 0)
    InventoryName = $inventory.InventoryName
    ControllerFamily = $controller.Family
    SoftwareVersion = $controller.SoftwareVersion
    Findings = $findings.ToArray()
})

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "Controller inventory validation failed for $($result.Path):`n$($messages -join "`n")"
}
