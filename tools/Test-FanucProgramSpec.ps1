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

function Test-AllowedRegisterWriteBlock {
    param(
        [int]$Start,
        [int]$Length
    )

    if ($Length -lt 1) {
        return $false
    }

    for ($register = $Start; $register -lt ($Start + $Length); $register++) {
        if (-not (Test-AllowedRegisterWrite -Register $register)) {
            return $false
        }
    }
    return $true
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

function Get-AllowedRunEntry {
    param([string]$Program)

    foreach ($entry in @($cellMap.Runs.Allowed)) {
        if ($entry.Program.ToUpperInvariant() -eq $Program.ToUpperInvariant()) {
            return $entry
        }
    }
    return $null
}

function Get-CallArgumentRule {
    param(
        [object]$CallEntry,
        [int]$Position
    )

    foreach ($rule in @($CallEntry.Arguments)) {
        if ([int]$rule.Position -eq $Position) {
            return $rule
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
        "remark" {
            if (-not $operation.text -or $operation.text.Trim().Length -eq 0) {
                Add-Finding -Rule "RemarkTextRequired" -Message "operations[$operationIndex].text is required for remark."
            } elseif ($operation.text.Length -gt 120) {
                Add-Finding -Rule "RemarkTooLong" -Message "operations[$operationIndex].text must be 120 characters or fewer."
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

                if ($null -ne $callEntry) {
                    $arguments = if ($operation.PSObject.Properties.Name -contains "arguments") { @($operation.arguments) } else { @() }
                    $argumentRules = @($callEntry.Arguments)
                    $requiredArgumentRules = @($argumentRules | Where-Object { -not ($_.PSObject.Properties.Name -contains "Required") -or $_.Required -ne $false })

                    if ($argumentRules.Count -gt 0 -and ($arguments.Count -lt $requiredArgumentRules.Count -or $arguments.Count -gt $argumentRules.Count)) {
                        Add-Finding -Rule "CallArgumentCount" -Message "operations[$operationIndex] calls $($operation.program) with $($arguments.Count) argument(s), but the cell map allows $($requiredArgumentRules.Count) to $($argumentRules.Count)."
                    }

                    $argumentIndex = 0
                    foreach ($argument in $arguments) {
                        $argumentIndex++
                        $rule = Get-CallArgumentRule -CallEntry $callEntry -Position $argumentIndex
                        if ($argumentRules.Count -gt 0 -and $null -eq $rule) {
                            Add-Finding -Rule "CallArgumentUnexpected" -Message "operations[$operationIndex].arguments[$argumentIndex] is not allowed by the $($operation.program) cell-map contract."
                            continue
                        }

                        if ($argument.type -notin @("string", "integer")) {
                            Add-Finding -Rule "CallArgumentType" -Message "operations[$operationIndex].arguments[$argumentIndex].type must be string or integer."
                            continue
                        }

                        if ($argument.type -eq "string") {
                            if ($argument.value -isnot [string] -or $argument.value -cnotmatch '^[A-Z0-9_ -]{1,32}$') {
                                Add-Finding -Rule "CallStringArgumentValue" -Message "operations[$operationIndex].arguments[$argumentIndex].value must be safe uppercase FANUC text."
                            } elseif ($null -ne $rule -and $rule.Type -and $rule.Type -ne "string") {
                                Add-Finding -Rule "CallArgumentContractType" -Message "operations[$operationIndex].arguments[$argumentIndex] must be $($rule.Type) for $($operation.program)."
                            } elseif ($null -ne $rule -and @($rule.AllowedValues).Count -gt 0 -and @($rule.AllowedValues | ForEach-Object { $_.ToUpperInvariant() }) -notcontains $argument.value.ToUpperInvariant()) {
                                Add-Finding -Rule "CallStringArgumentNotAllowed" -Message "operations[$operationIndex].arguments[$argumentIndex] value '$($argument.value)' is not allowed for $($operation.program)."
                            }
                        } elseif ($argument.type -eq "integer") {
                            if ($argument.value -isnot [int] -and $argument.value -isnot [long]) {
                                Add-Finding -Rule "CallIntegerArgumentValue" -Message "operations[$operationIndex].arguments[$argumentIndex].value must be an integer."
                            } elseif ($null -ne $rule -and $rule.Type -and $rule.Type -ne "integer") {
                                Add-Finding -Rule "CallArgumentContractType" -Message "operations[$operationIndex].arguments[$argumentIndex] must be $($rule.Type) for $($operation.program)."
                            } else {
                                $integerValue = [int]$argument.value
                                if ($null -ne $rule -and $null -ne $rule.Min -and $integerValue -lt [int]$rule.Min) {
                                    Add-Finding -Rule "CallIntegerArgumentMin" -Message "operations[$operationIndex].arguments[$argumentIndex] value $integerValue is below the $($operation.program) minimum $($rule.Min)."
                                }
                                if ($null -ne $rule -and $null -ne $rule.Max -and $integerValue -gt [int]$rule.Max) {
                                    Add-Finding -Rule "CallIntegerArgumentMax" -Message "operations[$operationIndex].arguments[$argumentIndex] value $integerValue is above the $($operation.program) maximum $($rule.Max)."
                                }
                                if ($null -ne $rule -and $null -ne $rule.RegisterWriteBlockLength -and -not (Test-AllowedRegisterWriteBlock -Start $integerValue -Length ([int]$rule.RegisterWriteBlockLength))) {
                                    Add-Finding -Rule "CallRegisterBlockNotAllowed" -Message "operations[$operationIndex].arguments[$argumentIndex] points $($operation.program) at R[$integerValue] through R[$($integerValue + [int]$rule.RegisterWriteBlockLength - 1)], which is not fully allowed by config\cell-map.psd1."
                                }
                            }
                        }
                    }
                }
            }
        }
        "runProgram" {
            if (-not $operation.program -or $operation.program -cnotmatch '^[A-Z][A-Z0-9_]{0,31}$') {
                Add-Finding -Rule "RunProgramRequired" -Message "operations[$operationIndex].program must be an uppercase FANUC-compatible program name."
            } else {
                $runEntry = Get-AllowedRunEntry -Program $operation.program
                if ($null -eq $runEntry) {
                    Add-Finding -Rule "RunProgramNotAllowed" -Message "operations[$operationIndex] runs $($operation.program), which is not allowed by config\cell-map.psd1."
                } elseif ($runEntry.MotionAllowed -eq $true) {
                    Add-Finding -Rule "RunProgramMotionNotSupported" -Message "operations[$operationIndex] runs $($operation.program), but motion-capable RUN targets are not supported by this generator stage."
                }
            }
        }
        "userAlarm" {
            if ($null -eq $operation.alarm -or [int]$operation.alarm -lt 1 -or [int]$operation.alarm -gt 999) {
                Add-Finding -Rule "UserAlarmRequired" -Message "operations[$operationIndex].alarm must be between 1 and 999."
            }
        }
        "label" {
            if ($null -eq $operation.label -or [int]$operation.label -lt 1 -or [int]$operation.label -gt 9999) {
                Add-Finding -Rule "LabelRequired" -Message "operations[$operationIndex].label must be between 1 and 9999."
            }
        }
        "jump" {
            if ($null -eq $operation.label -or [int]$operation.label -lt 1 -or [int]$operation.label -gt 9999) {
                Add-Finding -Rule "JumpLabelRequired" -Message "operations[$operationIndex].label must be between 1 and 9999."
            }
        }
        "ifRegisterEqualsJump" {
            if ($null -eq $operation.register -or [int]$operation.register -lt 1) {
                Add-Finding -Rule "IfRegisterRequired" -Message "operations[$operationIndex].register must be 1 or greater."
            }
            if ($null -eq $operation.value) {
                Add-Finding -Rule "IfRegisterValueRequired" -Message "operations[$operationIndex].value is required for ifRegisterEqualsJump."
            }
            if ($null -eq $operation.label -or [int]$operation.label -lt 1 -or [int]$operation.label -gt 9999) {
                Add-Finding -Rule "IfRegisterLabelRequired" -Message "operations[$operationIndex].label must be between 1 and 9999."
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
