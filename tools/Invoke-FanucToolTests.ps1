param()

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$tests = New-Object System.Collections.Generic.List[object]

function Add-TestResult {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Message = ""
    )

    $tests.Add([pscustomobject]@{
        Name = $Name
        Passed = $Passed
        Message = $Message
    })
}

function Invoke-ExpectPass {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    try {
        & $Command | Out-Null
        Add-TestResult -Name $Name -Passed $true
    } catch {
        Add-TestResult -Name $Name -Passed $false -Message $_.Exception.Message
    }
}

function Invoke-ExpectFail {
    param(
        [string]$Name,
        [scriptblock]$Command
    )

    try {
        & $Command | Out-Null
        Add-TestResult -Name $Name -Passed $false -Message "Expected failure but command passed."
    } catch {
        Add-TestResult -Name $Name -Passed $true -Message $_.Exception.Message
    }
}

$specValidator = Join-Path $scriptRoot "Test-FanucProgramSpec.ps1"
$lsValidator = Join-Path $scriptRoot "Test-FanucLsSafety.ps1"
$schemaValidator = Join-Path $scriptRoot "Test-FanucJsonSchema.ps1"
$cellMapValidator = Join-Path $scriptRoot "Test-FanucCellMap.ps1"
$cellObservationsValidator = Join-Path $scriptRoot "Test-FanucCellObservations.ps1"
$snpxReadonlyValidator = Join-Path $scriptRoot "Test-FanucSnpxReadonlyConfig.ps1"
$snpxWriteValidator = Join-Path $scriptRoot "Test-FanucSnpxWriteConfig.ps1"
$snpxSnapshotTool = Join-Path $scriptRoot "Invoke-FanucSnpxReadSnapshot.ps1"
$snpxWritePlanTool = Join-Path $scriptRoot "New-FanucSnpxWritePlan.ps1"
$snpxLiveReadTool = Join-Path $scriptRoot "Invoke-FanucSnpxLiveRead.ps1"
$snpxLiveWriteTool = Join-Path $scriptRoot "Invoke-FanucSnpxLiveWrite.ps1"
$statusSnapshotTool = Join-Path $scriptRoot "New-FanucCellStatusSnapshot.ps1"
$statusCompareTool = Join-Path $scriptRoot "Compare-FanucCellStatusSnapshot.ps1"
$schemaPath = Join-Path $projectRoot "schemas\program-spec.schema.json"

Invoke-ExpectPass -Name "CellMapValid" -Command {
    & $cellMapValidator -Quiet
}
Invoke-ExpectPass -Name "CellObservationsValid" -Command {
    & $cellObservationsValidator -Quiet
}
Invoke-ExpectPass -Name "SnpxReadonlyConfigValid" -Command {
    & $snpxReadonlyValidator -Quiet
}
Invoke-ExpectPass -Name "SnpxWriteConfigValid" -Command {
    & $snpxWriteValidator -Quiet
}
Invoke-ExpectPass -Name "SnpxPlanValuesValid" -Command {
    $valuesPath = Join-Path $projectRoot "generated\test-runs\snpx-values.json"
    & $snpxSnapshotTool -PlanOnly -OutputPath $valuesPath | Out-Null
    $values = Get-Content -LiteralPath $valuesPath -Raw | ConvertFrom-Json
    if ($values.registers.PSObject.Properties.Name -notcontains "R[97]") {
        throw "Expected SNPX plan values to include R[97]."
    }
    if ($values.ioSignals.PSObject.Properties.Name -notcontains "DO[1]") {
        throw "Expected SNPX plan values to include DO[1]."
    }
}
Invoke-ExpectPass -Name "SnpxWritePlanValid" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\snpx-write-plan.json"
    & $snpxWritePlanTool -Fanuc "R[99]" -Value 123 -OutputPath $planPath | Out-Null
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if ($plan.write.fanuc -ne "R[99]") {
        throw "Expected SNPX write plan for R[99]."
    }
    if ($plan.write.snpxAddress -ne "%R00013") {
        throw "Expected R[99] to map to %R00013."
    }
}
Invoke-ExpectPass -Name "SnpxLiveReadPlanValid" -Command {
    $evidencePath = Join-Path $projectRoot "generated\test-runs\snpx-live-read-plan.json"
    $result = & $snpxLiveReadTool -OutputPath $evidencePath
    if ($result.Executed) {
        throw "Dry-run SNPX live read plan should not execute."
    }
    $plan = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    if ($plan.commands.setasg.Count -lt 1) {
        throw "Expected dry-run SNPX live read plan to include SETASG commands."
    }
}
Invoke-ExpectPass -Name "SnpxLiveWritePlanValid" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\snpx-write-plan-approved.json"
    $evidencePath = Join-Path $projectRoot "generated\test-runs\snpx-live-write-plan.json"
    & $snpxWritePlanTool -Fanuc "R[99]" -Value 123 -OutputPath $planPath -Approved | Out-Null
    $result = & $snpxLiveWriteTool -PlanPath $planPath -OutputPath $evidencePath
    if ($result.Executed) {
        throw "Dry-run SNPX live write plan should not execute."
    }
    if ($result.SnpxAddress -ne "%R00013") {
        throw "Expected R[99] live write plan to use %R00013."
    }
}
Invoke-ExpectPass -Name "CellStatusSnapshotSample" -Command {
    $testRoot = Join-Path $projectRoot "generated\test-runs\cell-status"
    $planPath = Join-Path $projectRoot "generated\cell-status\latest\status-plan.json"
    $valuesPath = Join-Path $projectRoot "tests\fixtures\valid\cell-status-values.sample.json"
    $before = & $statusSnapshotTool -PlanPath $planPath -Label test-empty -OutputRoot $testRoot -Force
    $after = & $statusSnapshotTool -PlanPath $planPath -ValuesPath $valuesPath -Label test-populated -OutputRoot $testRoot -Force
    $comparisonPath = Join-Path $testRoot "comparison.json"
    $comparison = & $statusCompareTool -BeforePath $before.SnapshotPath -AfterPath $after.SnapshotPath -OutputPath $comparisonPath
    if ($comparison.ChangeCount -lt 1) {
        throw "Expected snapshot comparison to find changes."
    }
}
Invoke-ExpectPass -Name "SchemaValidSpec" -Command {
    & $schemaValidator -JsonPath (Join-Path $projectRoot "tests\fixtures\valid\AI_VALID.program-spec.json") -SchemaPath $schemaPath -Quiet
}
Invoke-ExpectFail -Name "SpecBadPrefixFails" -Command {
    & $specValidator -SpecPath (Join-Path $projectRoot "tests\fixtures\invalid\BAD_PREFIX.program-spec.json") -Quiet
}
Invoke-ExpectFail -Name "SpecBadOperationFails" -Command {
    & $specValidator -SpecPath (Join-Path $projectRoot "tests\fixtures\invalid\AI_BAD_OPERATION.program-spec.json") -Quiet
}
Invoke-ExpectFail -Name "SpecBadRegisterFails" -Command {
    & $specValidator -SpecPath (Join-Path $projectRoot "tests\fixtures\invalid\AI_BAD_REGISTER.program-spec.json") -Quiet
}
Invoke-ExpectFail -Name "SpecBadSignalFails" -Command {
    & $specValidator -SpecPath (Join-Path $projectRoot "tests\fixtures\invalid\AI_BAD_SIGNAL.program-spec.json") -Quiet
}
Invoke-ExpectFail -Name "SpecBadCallFails" -Command {
    & $specValidator -SpecPath (Join-Path $projectRoot "tests\fixtures\invalid\AI_BAD_CALL.program-spec.json") -Quiet
}
Invoke-ExpectPass -Name "LsValidPasses" -Command {
    & $lsValidator -LsPath (Join-Path $projectRoot "tests\fixtures\valid\AI_VALID.LS") -Quiet
}
Invoke-ExpectFail -Name "LsProgramMismatchFails" -Command {
    & $lsValidator -LsPath (Join-Path $projectRoot "tests\fixtures\invalid\AI_MISMATCH.LS") -Quiet
}
Invoke-ExpectFail -Name "LsBlockedPatternFails" -Command {
    & $lsValidator -LsPath (Join-Path $projectRoot "tests\fixtures\invalid\AI_BLOCKED.LS") -Quiet
}

$failed = @($tests | Where-Object { -not $_.Passed })
$tests
if ($failed.Count -gt 0) {
    throw "$($failed.Count) tool test(s) failed."
}
