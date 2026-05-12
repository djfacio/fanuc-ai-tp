param(
    [string]$ConfigPath = "..\config\snpx-readonly.psd1",
    [switch]$RequireEnabled,
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

$configPath = $resolvedConfig.Path
$config = Import-PowerShellDataFile -LiteralPath $configPath
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

if ($config.Protocol -ne "SNPX_V2") {
    Add-Finding -Rule "Protocol" -Message "Protocol must be SNPX_V2."
}

if ($config.MappingMode -ne "per-connection") {
    Add-Finding -Rule "MappingMode" -Message "MappingMode must be per-connection."
}

if (-not $config.AddressAssignment) {
    Add-Finding -Rule "AddressAssignment" -Message "AddressAssignment is required."
} else {
    if ($config.AddressAssignment.Mode -ne "project-owned-asg") {
        Add-Finding -Rule "AddressAssignmentMode" -Message "AddressAssignment.Mode must be project-owned-asg."
    }

    if ($config.AddressAssignment.Area -ne "%R") {
        Add-Finding -Rule "AddressAssignmentArea" -Message "AddressAssignment.Area must be %R for the ASG projection window."
    }

    if ($null -eq $config.AddressAssignment.SlotLimit -or [int]$config.AddressAssignment.SlotLimit -ne 80) {
        Add-Finding -Rule "AddressAssignmentSlotLimit" -Message "AddressAssignment.SlotLimit must document the 80-slot ASG cap."
    }
}

if (-not $config.RobotIp) {
    Add-Finding -Rule "RobotIp" -Message "RobotIp is required."
}

if ($null -eq $config.Port -or [int]$config.Port -lt 1 -or [int]$config.Port -gt 65535) {
    Add-Finding -Rule "Port" -Message "Port must be 1 through 65535."
}

if ($RequireEnabled -and -not [bool]$config.Enabled) {
    Add-Finding -Rule "Enabled" -Message "Config must be enabled for live reads."
}

$snapshotKeys = @{}
$snpxAddresses = @{}
$asgSlots = @{}
foreach ($read in @($config.Reads)) {
    if ($null -eq $read) {
        continue
    }

    if (-not $read.Fanuc -or $read.Fanuc -notmatch '^(R\[[1-9][0-9]*\]|D[IO]\[[1-9][0-9]*\]|R[IO]\[[1-9][0-9]*\])$') {
        Add-Finding -Rule "FanucAddress" -Message "Read entry '$($read.Name)' has invalid FANUC address '$($read.Fanuc)'."
    }

    if (-not $read.SnapshotKey) {
        Add-Finding -Rule "SnapshotKey" -Message "Read entry '$($read.Name)' must include SnapshotKey."
    } elseif ($snapshotKeys.ContainsKey($read.SnapshotKey)) {
        Add-Finding -Rule "SnapshotKeyDuplicate" -Message "SnapshotKey '$($read.SnapshotKey)' appears more than once."
    } else {
        $snapshotKeys[$read.SnapshotKey] = $true
    }

    if ($read.Type -notin @("int", "bool", "real", "string")) {
        Add-Finding -Rule "Type" -Message "Read entry '$($read.Name)' has unsupported Type '$($read.Type)'."
    }

    if ($read.Representation -notin @("word", "word-bool", "scaled-word", "real32", "string40")) {
        Add-Finding -Rule "Representation" -Message "Read entry '$($read.Name)' has unsupported Representation '$($read.Representation)'."
    }

    if ($null -eq $read.AsgSlot -or [int]$read.AsgSlot -lt 1 -or [int]$read.AsgSlot -gt 80) {
        Add-Finding -Rule "AsgSlot" -Message "Read entry '$($read.Name)' must use AsgSlot 1 through 80."
    } elseif ($asgSlots.ContainsKey([int]$read.AsgSlot)) {
        Add-Finding -Rule "AsgSlotDuplicate" -Message "AsgSlot '$($read.AsgSlot)' appears more than once."
    } else {
        $asgSlots[[int]$read.AsgSlot] = $true
    }

    if (-not $read.SetAsgRegion) {
        Add-Finding -Rule "SetAsgRegion" -Message "Read entry '$($read.Name)' must include SetAsgRegion."
    } elseif ($read.SetAsgRegion -ne $read.Fanuc) {
        Add-Finding -Rule "SetAsgRegionMatch" -Message "Read entry '$($read.Name)' must match Fanuc and SetAsgRegion until explicit transforms are supported."
    }

    if ($read.SetAsgDataType -notin @("INTEGER", "SHORT", "BYTE", "REAL", "BOOLEAN", "POSITION", "STRING")) {
        Add-Finding -Rule "SetAsgDataType" -Message "Read entry '$($read.Name)' has unsupported SetAsgDataType '$($read.SetAsgDataType)'."
    }

    if ($null -eq $read.SetAsgMultiply -or [int]$read.SetAsgMultiply -lt 0) {
        Add-Finding -Rule "SetAsgMultiply" -Message "Read entry '$($read.Name)' must include non-negative SetAsgMultiply."
    }

    if ($read.Representation -eq "scaled-word") {
        if ($read.Type -ne "real") {
            Add-Finding -Rule "ScaledWordType" -Message "Read entry '$($read.Name)' with Representation scaled-word must use Type real."
        }
        if ($null -eq $read.ScaleDivisor -or [decimal]$read.ScaleDivisor -le 0) {
            Add-Finding -Rule "ScaleDivisor" -Message "Read entry '$($read.Name)' with Representation scaled-word must include ScaleDivisor > 0."
        }
    }

    if ($read.SnpxArea -ne "%R") {
        Add-Finding -Rule "SnpxArea" -Message "Read entry '$($read.Name)' must project into %R."
    }

    if ($null -eq $read.SnpxStart -or [int]$read.SnpxStart -lt 1) {
        Add-Finding -Rule "SnpxStart" -Message "Read entry '$($read.Name)' must include a positive SnpxStart."
    }

    if ($null -eq $read.WordCount -or [int]$read.WordCount -lt 1) {
        Add-Finding -Rule "WordCount" -Message "Read entry '$($read.Name)' must include a positive WordCount."
    } elseif ($read.SetAsgDataType -in @("INTEGER", "SHORT", "BYTE", "REAL", "BOOLEAN") -and [int]$read.WordCount -ne 2) {
        Add-Finding -Rule "WordCount" -Message "Read entry '$($read.Name)' with SetAsgDataType '$($read.SetAsgDataType)' must use WordCount 2."
    }

    if ($read.SnpxAddress) {
        if ($read.SnpxAddress -notmatch '^%[A-Z]+[0-9]+$') {
            Add-Finding -Rule "SnpxAddressFormat" -Message "Read entry '$($read.Name)' has invalid SnpxAddress '$($read.SnpxAddress)'."
        } elseif ($snpxAddresses.ContainsKey($read.SnpxAddress.ToUpperInvariant())) {
            Add-Finding -Rule "SnpxAddressDuplicate" -Message "SnpxAddress '$($read.SnpxAddress)' appears more than once."
        } else {
            $snpxAddresses[$read.SnpxAddress.ToUpperInvariant()] = $true
        }
    }

    if ([bool]$config.Enabled -and -not $read.SnpxAddress) {
        Add-Finding -Rule "SnpxAddressRequired" -Message "Read entry '$($read.Name)' needs SnpxAddress before live reads are enabled."
    }
}

$result = New-Object psobject -Property ([ordered]@{
    Path = (Get-Item -LiteralPath $configPath).FullName
    IsValid = ($findings.Count -eq 0)
    Enabled = [bool]$config.Enabled
    Protocol = $config.Protocol
    MappingMode = $config.MappingMode
    RobotIp = $config.RobotIp
    Port = $config.Port
    ReadCount = @($config.Reads).Count
    AssignedAddressCount = $snpxAddresses.Count
    AsgSlotCount = $asgSlots.Count
    Findings = $findings.ToArray()
})

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "SNPX read-only config validation failed for $($result.Path):`n$($messages -join "`n")"
}
