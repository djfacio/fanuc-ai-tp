param(
    [string]$ConfigPath = "..\config\pcdk-snapshot.psd1",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig.Path
$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param(
        [string]$Path,
        [string]$Message
    )

    $findings.Add([pscustomobject]@{
        Path = $Path
        Message = $Message
    })
}

if ([int]$config.SchemaVersion -lt 1) {
    Add-Finding -Path "SchemaVersion" -Message "SchemaVersion must be at least 1."
}

foreach ($required in @("Pcdk", "Defaults", "SnapshotSections", "BlockedPcdkCapabilities")) {
    if ($config.Keys -notcontains $required) {
        Add-Finding -Path $required -Message "Missing required top-level key."
    }
}

if ($config.Pcdk) {
    foreach ($required in @("InstallRoot", "ComProgId", "TypeLibrary", "Documentation", "ExampleRoot")) {
        if (-not $config.Pcdk.$required) {
            Add-Finding -Path "Pcdk.$required" -Message "Missing required PCDK setting."
        }
    }
}

if ($config.Defaults) {
    if ([bool]$config.Defaults.ConnectReadOnly) {
        Add-Finding -Path "Defaults.ConnectReadOnly" -Message "PCDK snapshot defaults must not connect to a controller."
    }

    foreach ($limit in @("MaxPrograms", "MaxAlarms", "MaxNumericRegisters", "MaxStringRegisters", "MaxPositionRegisters", "MaxFrames", "MaxIoSignalsPerType", "ConnectionTimeoutSeconds")) {
        if ([int]$config.Defaults.$limit -lt 1) {
            Add-Finding -Path "Defaults.$limit" -Message "Limit must be at least 1."
        }
    }
}

$sections = @($config.SnapshotSections)
if ($sections.Count -lt 1) {
    Add-Finding -Path "SnapshotSections" -Message "At least one snapshot section is required."
}

foreach ($section in $sections) {
    if (-not $section.Name) {
        Add-Finding -Path "SnapshotSections" -Message "Each snapshot section requires a Name."
    }
    if (-not [bool]$section.ReadOnly) {
        Add-Finding -Path "SnapshotSections.$($section.Name)" -Message "Every first-phase PCDK snapshot section must be read-only."
    }
}

$blocked = @($config.BlockedPcdkCapabilities)
foreach ($capability in @("Task.Abort", "Tasks.AbortAll", "I/O.Value write", "Frame.Update", "Position.Record", "Position.MoveTo", "FTP.PutFile", "Program.Delete")) {
    if ($blocked -notcontains $capability) {
        Add-Finding -Path "BlockedPcdkCapabilities" -Message "Blocked capability '$capability' must be listed."
    }
}

$result = [pscustomobject]@{
    Path = (Get-Item -LiteralPath $resolvedConfig.Path).FullName
    IsValid = ($findings.Count -eq 0)
    SectionCount = $sections.Count
    BlockedCapabilityCount = $blocked.Count
    Findings = $findings.ToArray()
}

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Path): $($_.Message)" }
    throw "PCDK snapshot config validation failed:`n$($messages -join "`n")"
}
