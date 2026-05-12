param(
    [string]$ConfigPath = "..\config\interface-strategy.psd1",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}
$resolvedConfigPath = $resolvedConfig.Path

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath
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

if ($null -eq $config.SchemaVersion -or [int]$config.SchemaVersion -ne 1) {
    Add-Finding -Rule "SchemaVersionInvalid" -Message "SchemaVersion must be 1."
}

$interfaces = @{}
foreach ($interface in @($config.Interfaces)) {
    if ($null -eq $interface) {
        continue
    }

    if (-not $interface.Name -or $interface.Name -notmatch '^[a-z][a-z0-9-]*$') {
        Add-Finding -Rule "InterfaceNameInvalid" -Message "Interface name '$($interface.Name)' must be lowercase kebab-case."
        continue
    }
    if ($interfaces.ContainsKey($interface.Name)) {
        Add-Finding -Rule "InterfaceDuplicate" -Message "Interface '$($interface.Name)' appears more than once."
    }
    $interfaces[$interface.Name] = $interface

    foreach ($key in @("Enabled", "AllowsProgramRun", "AllowsRobotMotion", "AllowsLiveWrites")) {
        if ($null -eq $interface[$key] -or $interface[$key] -isnot [bool]) {
            Add-Finding -Rule "InterfaceBoolInvalid" -Message "$($interface.Name).$key must be true or false."
        }
    }
    if (-not $interface.Role) {
        Add-Finding -Rule "InterfaceRoleMissing" -Message "$($interface.Name) must describe Role."
    }
    if (@($interface.SafetyGates).Count -lt 1) {
        Add-Finding -Rule "InterfaceSafetyGatesMissing" -Message "$($interface.Name) must include SafetyGates."
    }

    if ($interface.Name -eq "karel-tcp-bridge" -and [bool]$interface.Enabled) {
        Add-Finding -Rule "KarelBridgePrematurelyEnabled" -Message "KAREL TCP bridge must stay disabled until robot-resident code, schemas, deployment, rollback, and tests are reviewed."
    }
    if ([bool]$interface.AllowsRobotMotion -and $interface.Name -ne "roboguide") {
        Add-Finding -Rule "PhysicalMotionInterfaceBlocked" -Message "$($interface.Name) must not allow robot motion in this strategy."
    }
    if ([bool]$interface.AllowsProgramRun -and $interface.Name -ne "roboguide") {
        Add-Finding -Rule "ProgramRunInterfaceBlocked" -Message "$($interface.Name) must not run programs on the physical controller."
    }
}

foreach ($required in @("ftp-tp-artifact", "snpx-v2", "karel-tcp-bridge", "pcdk", "roboguide")) {
    if (-not $interfaces.ContainsKey($required)) {
        Add-Finding -Rule "InterfaceMissing" -Message "Interface '$required' is required."
    }
}

foreach ($schema in @($config.MessageSchemas)) {
    if ($null -eq $schema) {
        continue
    }

    if (-not $schema.Name -or $schema.Name -notmatch '^[a-z][a-z0-9-]*(\.[a-z][a-z0-9-]*)+$') {
        Add-Finding -Rule "MessageSchemaNameInvalid" -Message "Message schema '$($schema.Name)' must use dotted lowercase names."
    }
    if (-not $schema.Interface -or -not $interfaces.ContainsKey($schema.Interface)) {
        Add-Finding -Rule "MessageSchemaInterfaceMissing" -Message "Message schema '$($schema.Name)' references unknown interface '$($schema.Interface)'."
    }
    if (@($schema.RequiredFields).Count -lt 1) {
        Add-Finding -Rule "MessageSchemaFieldsMissing" -Message "Message schema '$($schema.Name)' must include RequiredFields."
    }
    if ([bool]$schema.Enabled) {
        Add-Finding -Rule "MessageSchemaPrematurelyEnabled" -Message "Message schema '$($schema.Name)' must stay disabled until implementation exists."
    }
    if ([bool]$schema.AllowsWrites -and $schema.Name -notmatch '^command\.reviewed-write\.') {
        Add-Finding -Rule "MessageSchemaWriteNameInvalid" -Message "Write-capable schema '$($schema.Name)' must use command.reviewed-write.* naming."
    }
}

$result = New-Object psobject -Property ([ordered]@{
    Path = (Get-Item -LiteralPath $resolvedConfigPath).FullName
    IsValid = ($findings.Count -eq 0)
    InterfaceCount = @($config.Interfaces).Count
    MessageSchemaCount = @($config.MessageSchemas).Count
    Findings = $findings.ToArray()
})

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "Interface strategy validation failed for $($result.Path):`n$($messages -join "`n")"
}
