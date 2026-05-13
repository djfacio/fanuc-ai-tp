param(
    [string]$ConfigPath = "..\config\pcdk-snapshot.psd1",
    [string]$OutputPath = "generated\pcdk\controller-snapshot.json",
    [string]$HostName = "",
    [switch]$ConnectReadOnly,
    [switch]$SkipComProbe
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

function Resolve-ConfigPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    return (Resolve-Path -LiteralPath (Join-Path $scriptRoot $Path)).Path
}

function Get-PropertyValue {
    param(
        [object]$Object,
        [string]$Name,
        [object]$Default = $null
    )

    try {
        return $Object.$Name
    } catch {
        return $Default
    }
}

function Add-LimitedItems {
    param(
        [object]$Collection,
        [int]$Limit,
        [scriptblock]$Map
    )

    $items = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Collection) {
        return $items.ToArray()
    }

    $count = 0
    foreach ($item in $Collection) {
        if ($count -ge $Limit) {
            break
        }

        try {
            $items.Add((& $Map $item))
            $count++
        } catch {
            $items.Add([pscustomobject]@{
                error = $_.Exception.Message
            })
            $count++
        }
    }

    return $items.ToArray()
}

$resolvedConfigPath = Resolve-ConfigPath -Path $ConfigPath
$validator = Join-Path $scriptRoot "Test-FanucPcdkSnapshotConfig.ps1"
& $validator -ConfigPath $resolvedConfigPath -Quiet

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath
$pcdkRoot = $config.Pcdk.InstallRoot
$documentationPath = Join-Path $pcdkRoot $config.Pcdk.Documentation
$typeLibraryPath = Join-Path $pcdkRoot $config.Pcdk.TypeLibrary
$exampleRootPath = Join-Path $pcdkRoot $config.Pcdk.ExampleRoot
$findings = New-Object System.Collections.Generic.List[string]

$comObjectCreated = $false
$robot = $null
if (-not $SkipComProbe) {
    try {
        $robot = New-Object -ComObject $config.Pcdk.ComProgId
        $comObjectCreated = $true
    } catch {
        $findings.Add("Unable to create PCDK COM object '$($config.Pcdk.ComProgId)': $($_.Exception.Message)")
    }
}

$connected = $false
$values = [ordered]@{
    identity = [ordered]@{}
    programs = @()
    tasks = @()
    alarms = @()
    registers = @()
    positionRegisters = @()
    frames = @()
    currentPosition = [ordered]@{}
    io = @()
    features = @()
}

if ($ConnectReadOnly) {
    if ([string]::IsNullOrWhiteSpace($HostName)) {
        throw "HostName is required with -ConnectReadOnly."
    }
    if (-not $robot) {
        $robot = New-Object -ComObject $config.Pcdk.ComProgId
        $comObjectCreated = $true
    }

    $timeoutAt = (Get-Date).AddSeconds([int]$config.Defaults.ConnectionTimeoutSeconds)
    try {
        $robot.ConnectEx($HostName, $true, 0, 2)
        while (-not [bool](Get-PropertyValue -Object $robot -Name "IsConnected" -Default $false)) {
            if ((Get-Date) -ge $timeoutAt) {
                throw "Timed out waiting for PCDK connection to $HostName."
            }
            Start-Sleep -Milliseconds 250
        }
        $connected = $true
    } catch {
        $findings.Add("PCDK read-only connection failed: $($_.Exception.Message)")
    }

    if ($connected) {
        try {
            $sysInfo = Get-PropertyValue -Object $robot -Name "SysInfo"
            $values.identity["hostName"] = $HostName
            $values.identity["isConnected"] = [bool](Get-PropertyValue -Object $robot -Name "IsConnected" -Default $false)
            if ($sysInfo) {
                $values.identity["startMode"] = (Get-PropertyValue -Object $sysInfo -Name "StartMode")
                $values.identity["clock"] = (Get-PropertyValue -Object $sysInfo -Name "Clock")
                $values.identity["permMemFreeKb"] = (Get-PropertyValue -Object $sysInfo -Name "PermMemFree")
                $values.identity["tppMemFreeKb"] = (Get-PropertyValue -Object $sysInfo -Name "TPPMemFree")
            }
        } catch {
            $findings.Add("PCDK identity read failed: $($_.Exception.Message)")
        }

        try {
            $programs = Get-PropertyValue -Object $robot -Name "Programs"
            $values.programs = Add-LimitedItems -Collection $programs -Limit ([int]$config.Defaults.MaxPrograms) -Map {
                param($program)
                [pscustomobject]@{
                    name = (Get-PropertyValue -Object $program -Name "Name" -Default "")
                    invisible = (Get-PropertyValue -Object $program -Name "Invisible" -Default $null)
                    created = (Get-PropertyValue -Object $program -Name "Created" -Default $null)
                    modified = (Get-PropertyValue -Object $program -Name "Modified" -Default $null)
                }
            }
            $values.identity["selectedProgram"] = (Get-PropertyValue -Object $programs -Name "Selected" -Default "")
        } catch {
            $findings.Add("PCDK program read failed: $($_.Exception.Message)")
        }

        try {
            $alarms = Get-PropertyValue -Object $robot -Name "Alarms"
            $values.alarms = Add-LimitedItems -Collection $alarms -Limit ([int]$config.Defaults.MaxAlarms) -Map {
                param($alarm)
                [pscustomobject]@{
                    mnemonic = (Get-PropertyValue -Object $alarm -Name "ErrorMnemonic" -Default "")
                    message = (Get-PropertyValue -Object $alarm -Name "ErrorMessage" -Default "")
                    severity = (Get-PropertyValue -Object $alarm -Name "Severity" -Default $null)
                }
            }
        } catch {
            $findings.Add("PCDK alarm read failed: $($_.Exception.Message)")
        }

        try {
            $tasks = Get-PropertyValue -Object $robot -Name "Tasks"
            $values.tasks = Add-LimitedItems -Collection $tasks -Limit 50 -Map {
                param($task)
                [pscustomobject]@{
                    name = (Get-PropertyValue -Object $task -Name "Name" -Default "")
                    lineNumber = (Get-PropertyValue -Object $task -Name "LineNumber" -Default $null)
                    programName = (Get-PropertyValue -Object $task -Name "ProgramName" -Default "")
                    status = (Get-PropertyValue -Object $task -Name "Status" -Default $null)
                }
            }
        } catch {
            $findings.Add("PCDK task read failed: $($_.Exception.Message)")
        }

        try {
            $numericRegisters = Get-PropertyValue -Object $robot -Name "RegNumerics"
            $values.registers = Add-LimitedItems -Collection $numericRegisters -Limit ([int]$config.Defaults.MaxNumericRegisters) -Map {
                param($var)
                $value = Get-PropertyValue -Object $var -Name "Value"
                [pscustomobject]@{
                    fieldName = (Get-PropertyValue -Object $var -Name "FieldName" -Default "")
                    value = (Get-PropertyValue -Object $value -Name "Value" -Default $value)
                    comment = (Get-PropertyValue -Object $value -Name "Comment" -Default "")
                }
            }
        } catch {
            $findings.Add("PCDK numeric register read failed: $($_.Exception.Message)")
        }
    }
}

$sections = @($config.SnapshotSections | ForEach-Object {
    [pscustomobject]@{
        name = $_.Name
        enabled = [bool]$_.Enabled
        readOnly = [bool]$_.ReadOnly
        description = $_.Description
    }
})

$artifact = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    source = "pcdk"
    collectionMode = if ($ConnectReadOnly) { "live-read" } else { "plan" }
    liveRobotCommandsExecuted = [bool]$ConnectReadOnly
    controllerWritesExecuted = $false
    pcdk = [ordered]@{
        required = [bool]$config.Pcdk.Required
        installRoot = $pcdkRoot
        installFound = (Test-Path -LiteralPath $pcdkRoot)
        comProgId = $config.Pcdk.ComProgId
        comObjectCreated = $comObjectCreated
        documentationFound = (Test-Path -LiteralPath $documentationPath)
        typeLibraryFound = (Test-Path -LiteralPath $typeLibraryPath)
        exampleRootFound = (Test-Path -LiteralPath $exampleRootPath)
        versionNote = "PCDK version should be recorded from the installed readme/documentation during review."
    }
    connection = [ordered]@{
        hostName = $HostName
        requested = [bool]$ConnectReadOnly
        connected = $connected
        timeoutSeconds = [int]$config.Defaults.ConnectionTimeoutSeconds
    }
    sections = $sections
    values = $values
    blockedCapabilities = @($config.BlockedPcdkCapabilities)
    findings = $findings.ToArray()
}

if ($robot -and [System.Runtime.InteropServices.Marshal]::IsComObject($robot)) {
    try {
        if ($connected) {
            $robot.Disconnect()
        }
    } catch {
        $findings.Add("PCDK disconnect failed: $($_.Exception.Message)")
    } finally {
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($robot) | Out-Null
    }
}

$resolvedOutputPath = Resolve-ProjectPath -Path $OutputPath
$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$artifact | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

[pscustomobject]@{
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
    CollectionMode = $artifact.collectionMode
    LiveRobotCommandsExecuted = $artifact.liveRobotCommandsExecuted
    ControllerWritesExecuted = $artifact.controllerWritesExecuted
    PcdkInstallFound = $artifact.pcdk.installFound
    ComObjectCreated = $artifact.pcdk.comObjectCreated
    Connected = $artifact.connection.connected
    FindingCount = $artifact.findings.Count
    Findings = $artifact.findings
}
