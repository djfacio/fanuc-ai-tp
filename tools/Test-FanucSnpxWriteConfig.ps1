param(
    [string]$ConfigPath = "..\config\snpx-writes.psd1",
    [switch]$RequireEnabled,
    [switch]$Quiet
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

if ($config.DefaultMode -ne "plan") {
    Add-Finding -Rule "DefaultMode" -Message "DefaultMode must stay plan until live write tooling is commissioned."
}

if (-not [bool]$config.RequireHumanApproval) {
    Add-Finding -Rule "HumanApproval" -Message "SNPX writes must require human approval."
}

if ($RequireEnabled -and -not [bool]$config.Enabled) {
    Add-Finding -Rule "Enabled" -Message "Config must be enabled for live SNPX writes."
}

$mappingPath = Resolve-ProjectPath $config.MappingSource
$cellMapPath = Resolve-ProjectPath $config.CellMapSource

if (-not (Test-Path -LiteralPath $mappingPath)) {
    Add-Finding -Rule "MappingSource" -Message "MappingSource '$($config.MappingSource)' does not exist."
}

if (-not (Test-Path -LiteralPath $cellMapPath)) {
    Add-Finding -Rule "CellMapSource" -Message "CellMapSource '$($config.CellMapSource)' does not exist."
}

$mappingReads = @{}
if (Test-Path -LiteralPath $mappingPath) {
    $mappingValidator = Join-Path $scriptRoot "Test-FanucSnpxReadonlyConfig.ps1"
    & $mappingValidator -ConfigPath $mappingPath -Quiet
    $mapping = Import-PowerShellDataFile -LiteralPath $mappingPath
    foreach ($read in @($mapping.Reads)) {
        if ($read.Fanuc) {
            $mappingReads[$read.Fanuc.ToUpperInvariant()] = $read
        }
    }
}

$allowedRegisters = @{}
$allowedSignals = @{}
$allowedRegisterRanges = New-Object System.Collections.Generic.List[object]
$allowedSignalRanges = New-Object System.Collections.Generic.List[object]
if (Test-Path -LiteralPath $cellMapPath) {
    $cellMapValidator = Join-Path $scriptRoot "Test-FanucCellMap.ps1"
    & $cellMapValidator -CellMapPath $cellMapPath -Quiet
    $cellMap = Import-PowerShellDataFile -LiteralPath $cellMapPath

    foreach ($range in @($cellMap.RegisterWrites.AllowedRanges)) {
        $allowedRegisterRanges.Add([pscustomobject]@{
            Start = [int]$range.Start
            End = [int]$range.End
        })
    }

    foreach ($entry in @($cellMap.RegisterWrites.Allowed)) {
        $allowedRegisters[[int]$entry.Register] = $true
    }

    foreach ($range in @($cellMap.IoWrites.AllowedRanges)) {
        $allowedSignalRanges.Add([pscustomobject]@{
            Type = $range.Type.ToUpperInvariant()
            Start = [int]$range.Start
            End = [int]$range.End
            SafeStates = @($range.SafeStates | ForEach-Object { $_.ToUpperInvariant() })
        })
    }

    foreach ($entry in @($cellMap.IoWrites.Allowed)) {
        $allowedSignals[$entry.Signal.ToUpperInvariant()] = @($entry.SafeStates | ForEach-Object { $_.ToUpperInvariant() })
    }
}

function Test-CellMapRegisterAllowed {
    param([int]$Register)

    if ($allowedRegisters.ContainsKey($Register)) {
        return $true
    }

    foreach ($range in $allowedRegisterRanges) {
        if ($Register -ge $range.Start -and $Register -le $range.End) {
            return $true
        }
    }

    return $false
}

function Get-CellMapSignalSafeStates {
    param([string]$FanucKey)

    if ($allowedSignals.ContainsKey($FanucKey)) {
        return @($allowedSignals[$FanucKey])
    }

    if ($FanucKey -match '^(DO|RO)\[(\d+)\]$') {
        $signalType = $Matches[1]
        $signalNumber = [int]$Matches[2]
        foreach ($range in $allowedSignalRanges) {
            if ($range.Type -eq $signalType -and $signalNumber -ge $range.Start -and $signalNumber -le $range.End) {
                return @($range.SafeStates)
            }
        }
    }

    return $null
}

$fanucWrites = @{}
foreach ($write in @($config.AllowedWrites)) {
    if ($null -eq $write) {
        continue
    }

    if (-not $write.Fanuc -or $write.Fanuc -notmatch '^(R\[[1-9][0-9]*\]|D[IO]\[[1-9][0-9]*\]|R[IO]\[[1-9][0-9]*\])$') {
        Add-Finding -Rule "FanucAddress" -Message "Write entry '$($write.Name)' has invalid FANUC address '$($write.Fanuc)'."
        continue
    }

    $fanucKey = $write.Fanuc.ToUpperInvariant()
    if ($fanucWrites.ContainsKey($fanucKey)) {
        Add-Finding -Rule "FanucDuplicate" -Message "Write entry '$fanucKey' appears more than once."
    } else {
        $fanucWrites[$fanucKey] = $true
    }

    if ($write.Type -notin @("int", "bool", "real", "string")) {
        Add-Finding -Rule "Type" -Message "Write entry '$($write.Name)' has unsupported Type '$($write.Type)'."
    }

    if ($write.Transport -ne "asg-projection") {
        Add-Finding -Rule "Transport" -Message "Write entry '$($write.Name)' must use asg-projection until direct-bit writes are separately commissioned."
    }

    if (-not $write.SnpxAddress -or $write.SnpxAddress -notmatch '^%R[0-9]+$') {
        Add-Finding -Rule "SnpxAddress" -Message "Write entry '$($write.Name)' must include a %R SnpxAddress."
    }

    if ($null -eq $write.WordCount -or [int]$write.WordCount -lt 1) {
        Add-Finding -Rule "WordCount" -Message "Write entry '$($write.Name)' must include a positive WordCount."
    }

    if (-not $mappingReads.ContainsKey($fanucKey)) {
        Add-Finding -Rule "MappingMissing" -Message "Write entry '$fanucKey' is not present in the SNPX ASG mapping source."
    } else {
        $mapped = $mappingReads[$fanucKey]
        if ($write.SnpxAddress -ne $mapped.SnpxAddress) {
            Add-Finding -Rule "MappingMismatch" -Message "Write entry '$fanucKey' uses $($write.SnpxAddress), but mapping source uses $($mapped.SnpxAddress)."
        }
        if ($null -ne $write.WordCount -and [int]$write.WordCount -ne [int]$mapped.WordCount) {
            Add-Finding -Rule "MappingWordCountMismatch" -Message "Write entry '$fanucKey' uses WordCount $($write.WordCount), but mapping source uses $($mapped.WordCount)."
        }
    }

    if ([bool]$write.RequiresCellMap) {
        if ($fanucKey -match '^R\[(\d+)\]$') {
            $register = [int]$Matches[1]
            if (-not (Test-CellMapRegisterAllowed -Register $register)) {
                Add-Finding -Rule "CellMapRegisterMissing" -Message "Write entry '$fanucKey' is not approved in config\cell-map.psd1."
            }
        } elseif ($fanucKey -match '^(DO|RO)\[\d+\]$') {
            $cellStates = @(Get-CellMapSignalSafeStates -FanucKey $fanucKey)
            if ($null -eq $cellStates) {
                Add-Finding -Rule "CellMapSignalMissing" -Message "Write entry '$fanucKey' is not approved in config\cell-map.psd1."
            } elseif ($write.AllowedStates) {
                foreach ($state in @($write.AllowedStates)) {
                    if ($cellStates -notcontains $state.ToUpperInvariant()) {
                        Add-Finding -Rule "CellMapSignalStateMissing" -Message "Write entry '$fanucKey' allows state '$state', but cell map does not."
                    }
                }
            }
        }
    }

    if ($write.Type -eq "int") {
        if ($null -eq $write.Min -or $null -eq $write.Max -or [int]$write.Min -gt [int]$write.Max) {
            Add-Finding -Rule "IntRange" -Message "Integer write '$fanucKey' must include Min <= Max."
        }
    }

    if ($write.Type -eq "bool" -and @($write.AllowedStates).Count -eq 0) {
        Add-Finding -Rule "BoolStates" -Message "Boolean write '$fanucKey' must include AllowedStates."
    }
}

$result = New-Object psobject -Property ([ordered]@{
    Path = (Get-Item -LiteralPath $configPath).FullName
    IsValid = ($findings.Count -eq 0)
    Enabled = [bool]$config.Enabled
    Protocol = $config.Protocol
    MappingMode = $config.MappingMode
    DefaultMode = $config.DefaultMode
    AllowedWriteCount = @($config.AllowedWrites).Count
    Findings = $findings.ToArray()
})

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "SNPX write config validation failed for $($result.Path):`n$($messages -join "`n")"
}
