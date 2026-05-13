param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$ConfigPath = "..\config\robot.psd1",
    [string]$CellMapPath = "..\config\cell-map.psd1",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig

if ([System.IO.Path]::IsPathRooted($CellMapPath)) {
    $resolvedCellMap = Resolve-Path -LiteralPath $CellMapPath
} else {
    $resolvedCellMap = Resolve-Path -LiteralPath (Join-Path $scriptRoot $CellMapPath)
}

$cellMapValidator = Join-Path $scriptRoot "Test-FanucCellMap.ps1"
& $cellMapValidator -CellMapPath $resolvedCellMap -Quiet
$cellMap = Import-PowerShellDataFile -LiteralPath $resolvedCellMap

$resolvedSpec = Resolve-Path -LiteralPath $SpecPath
$specText = Get-Content -LiteralPath $resolvedSpec -Raw
$spec = $specText | ConvertFrom-Json

$result = [ordered]@{
    Path = (Get-Item -LiteralPath $resolvedSpec).FullName
    ProgramName = $spec.programName
    IsValid = $true
    Findings = @()
}

function Add-Finding {
    param(
        [string]$Rule,
        [string]$Message
    )

    $result.IsValid = $false
    $result.Findings += [pscustomobject]@{
        Rule = $Rule
        Message = $Message
    }
}

function Test-AllowedRegisterWrite {
    param([int]$Register)

    foreach ($range in @($cellMap.RegisterWrites.AllowedRanges)) {
        if ($null -ne $range.Start -and $null -ne $range.End -and $Register -ge [int]$range.Start -and $Register -le [int]$range.End) {
            return $true
        }
    }

    foreach ($entry in @($cellMap.RegisterWrites.Allowed)) {
        if ([int]$entry.Register -eq $Register) {
            return $true
        }
    }
    return $false
}

function Test-AllowedIoWrite {
    param(
        [string]$Signal,
        [bool]$State
    )

    $stateText = if ($State) { "ON" } else { "OFF" }
    $normalizedSignal = $Signal.ToUpperInvariant()
    foreach ($entry in @($cellMap.IoWrites.Allowed)) {
        if ($entry.Signal.ToUpperInvariant() -ne $normalizedSignal) {
            continue
        }

        if ($null -eq $entry.SafeStates -or @($entry.SafeStates).Count -eq 0) {
            return $true
        }

        return (@($entry.SafeStates | ForEach-Object { $_.ToUpperInvariant() }) -contains $stateText)
    }

    if ($normalizedSignal -match '^(DO|RO)\[(\d+)\]$') {
        $signalType = $Matches[1]
        $signalNumber = [int]$Matches[2]
        foreach ($range in @($cellMap.IoWrites.AllowedRanges)) {
            if ($range.Type.ToUpperInvariant() -ne $signalType) {
                continue
            }
            if ($signalNumber -lt [int]$range.Start -or $signalNumber -gt [int]$range.End) {
                continue
            }

            if ($null -eq $range.SafeStates -or @($range.SafeStates).Count -eq 0) {
                return $true
            }

            return (@($range.SafeStates | ForEach-Object { $_.ToUpperInvariant() }) -contains $stateText)
        }
    }

    return $false
}

function Get-AllowedCallEntry {
    param([string]$Program)

    foreach ($entry in @($cellMap.Calls.Allowed)) {
        if ($entry.Program.ToUpperInvariant() -eq $Program.ToUpperInvariant()) {
            return $entry
        }
    }
    return $null
}

function Get-AllowedProgramPrefixes {
    param([object]$Config)

    $prefixes = New-Object System.Collections.Generic.List[string]
    if ($Config.ProgramPrefix) {
        $prefixes.Add($Config.ProgramPrefix.ToUpperInvariant())
    }
    foreach ($prefix in @($Config.LegacyProgramPrefixes)) {
        if ($prefix) {
            $prefixes.Add($prefix.ToUpperInvariant())
        }
    }
    return @($prefixes.ToArray() | Sort-Object -Unique)
}

$allowedProgramPrefixes = @(Get-AllowedProgramPrefixes -Config $config)

$schemaPath = Join-Path $projectRoot "schemas\program-spec.schema.json"
$schemaValidator = Join-Path $scriptRoot "Test-FanucJsonSchema.ps1"
try {
    & $schemaValidator -JsonPath $resolvedSpec -SchemaPath $schemaPath -Quiet
} catch {
    Add-Finding -Rule "JsonSchema" -Message $_.Exception.Message
}

if (-not $spec.programName) {
    Add-Finding -Rule "ProgramNameRequired" -Message "programName is required."
} elseif ($spec.programName -cnotmatch '^[A-Z][A-Z0-9_]{0,31}$') {
    Add-Finding -Rule "ProgramNameFormat" -Message "programName must be uppercase FANUC-compatible text with 32 characters or fewer."
} elseif (-not @($allowedProgramPrefixes | Where-Object { $spec.programName.StartsWith($_) }).Count) {
    Add-Finding -Rule "ProgramPrefix" -Message "programName must start with one of: $($allowedProgramPrefixes -join ', ')."
}

if (-not $spec.intent -or $spec.intent.Trim().Length -eq 0) {
    Add-Finding -Rule "IntentRequired" -Message "intent is required."
}

if (-not $spec.safety) {
    Add-Finding -Rule "SafetyRequired" -Message "safety is required."
} else {
    if ($spec.safety.motionAllowed -ne $false) {
        Add-Finding -Rule "MotionNotSupported" -Message "This generator stage only accepts specs with safety.motionAllowed=false."
    }

    if ($null -eq $spec.safety.requiresHumanReview) {
        Add-Finding -Rule "HumanReviewRequired" -Message "safety.requiresHumanReview is required."
    }
}

$operations = @($spec.operations)
if ($operations.Count -eq 0) {
    Add-Finding -Rule "OperationsRequired" -Message "At least one operation is required."
}

$operationIndex = 0
foreach ($operation in $operations) {
    $operationIndex++
    switch ($operation.type) {
        "message" {
            if (-not $operation.text -or $operation.text.Trim().Length -eq 0) {
                Add-Finding -Rule "MessageTextRequired" -Message "operations[$operationIndex].text is required for message."
            } elseif ($operation.text.Length -gt 24) {
                Add-Finding -Rule "MessageTooLong" -Message "operations[$operationIndex].text must be 24 characters or fewer."
            }
        }
        "registerWrite" {
            if ($null -eq $operation.register -or $operation.register -lt 1) {
                Add-Finding -Rule "RegisterRequired" -Message "operations[$operationIndex].register must be 1 or greater."
            } elseif (-not (Test-AllowedRegisterWrite -Register ([int]$operation.register))) {
                Add-Finding -Rule "RegisterNotAllowed" -Message "operations[$operationIndex] writes R[$($operation.register)], which is not allowed by config\cell-map.psd1."
            }
            if ($null -eq $operation.value) {
                Add-Finding -Rule "RegisterValueRequired" -Message "operations[$operationIndex].value is required for registerWrite."
            }
        }
        "ioWrite" {
            if (-not $operation.signal -or $operation.signal -notmatch '^(DO|RO)\[[1-9][0-9]*\]$') {
                Add-Finding -Rule "SignalFormat" -Message "operations[$operationIndex].signal must look like DO[1] or RO[1]."
            } elseif ($null -ne $operation.state -and -not (Test-AllowedIoWrite -Signal $operation.signal -State ([bool]$operation.state))) {
                Add-Finding -Rule "SignalNotAllowed" -Message "operations[$operationIndex] writes $($operation.signal), which is not allowed by config\cell-map.psd1."
            }
            if ($null -eq $operation.state) {
                Add-Finding -Rule "SignalStateRequired" -Message "operations[$operationIndex].state is required for ioWrite."
            }
        }
        "wait" {
            if ($null -eq $operation.seconds -or $operation.seconds -lt 0) {
                Add-Finding -Rule "WaitSecondsRequired" -Message "operations[$operationIndex].seconds must be 0 or greater."
            }
        }
        "comment" {
            if (-not $operation.text -or $operation.text.Trim().Length -eq 0) {
                Add-Finding -Rule "CommentTextRequired" -Message "operations[$operationIndex].text is required for comment."
            }
        }
        "diagnosticCheck" {
            if (-not $operation.name -or $operation.name.Trim().Length -eq 0) {
                Add-Finding -Rule "DiagnosticNameRequired" -Message "operations[$operationIndex].name is required for diagnosticCheck."
            }
            if (-not $operation.text -or $operation.text.Trim().Length -eq 0) {
                Add-Finding -Rule "DiagnosticTextRequired" -Message "operations[$operationIndex].text is required for diagnosticCheck."
            }
        }
        "callProgram" {
            if (-not $operation.program -or $operation.program -cnotmatch '^[A-Z][A-Z0-9_]{0,31}$') {
                Add-Finding -Rule "CallProgramRequired" -Message "operations[$operationIndex].program must be an uppercase FANUC-compatible program name."
            } else {
                $callEntry = Get-AllowedCallEntry -Program $operation.program
                if ($null -eq $callEntry) {
                    Add-Finding -Rule "CallProgramNotAllowed" -Message "operations[$operationIndex] calls $($operation.program), which is not allowed by config\cell-map.psd1."
                } elseif ($callEntry.MotionAllowed -eq $true) {
                    Add-Finding -Rule "CallProgramMotionNotSupported" -Message "operations[$operationIndex] calls $($operation.program), but motion-capable CALL targets are not supported by this generator stage."
                }
            }
        }
        default {
            Add-Finding -Rule "UnsupportedOperation" -Message "operations[$operationIndex].type '$($operation.type)' is not supported."
        }
    }
}

$output = [pscustomobject]$result
if (-not $Quiet) {
    $output
}

if (-not $result.IsValid) {
    $messages = $result.Findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "Program spec validation failed for $($result.Path):`n$($messages -join "`n")"
}
