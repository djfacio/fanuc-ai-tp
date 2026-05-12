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
$controllerInventoryValidator = Join-Path $scriptRoot "Test-FanucControllerInventory.ps1"
$controllerCapabilityTool = Join-Path $scriptRoot "Get-FanucControllerCapability.ps1"
$templateCatalogValidator = Join-Path $scriptRoot "Test-FanucTemplateCatalog.ps1"
$templateCatalogTool = Join-Path $scriptRoot "Get-FanucTemplateCatalog.ps1"
$roboguideEvidenceValidator = Join-Path $scriptRoot "Test-FanucRoboguideEvidenceConfig.ps1"
$roboguideEvidencePacketTool = Join-Path $scriptRoot "New-FanucRoboguideEvidencePacket.ps1"
$interfaceStrategyValidator = Join-Path $scriptRoot "Test-FanucInterfaceStrategy.ps1"
$interfaceStrategyTool = Join-Path $scriptRoot "Get-FanucInterfaceStrategy.ps1"
$snpxReadonlyValidator = Join-Path $scriptRoot "Test-FanucSnpxReadonlyConfig.ps1"
$snpxWriteValidator = Join-Path $scriptRoot "Test-FanucSnpxWriteConfig.ps1"
$snpxMatrixTool = Join-Path $scriptRoot "Get-FanucSnpxCommissioningMatrix.ps1"
$snpxSnapshotTool = Join-Path $scriptRoot "Invoke-FanucSnpxReadSnapshot.ps1"
$snpxWritePlanTool = Join-Path $scriptRoot "New-FanucSnpxWritePlan.ps1"
$snpxLiveReadTool = Join-Path $scriptRoot "Invoke-FanucSnpxLiveRead.ps1"
$snpxLiveWriteTool = Join-Path $scriptRoot "Invoke-FanucSnpxLiveWrite.ps1"
$statusPlanTool = Join-Path $scriptRoot "New-FanucCellStatusPlan.ps1"
$statusSnapshotTool = Join-Path $scriptRoot "New-FanucCellStatusSnapshot.ps1"
$statusCompareTool = Join-Path $scriptRoot "Compare-FanucCellStatusSnapshot.ps1"
$schemaPath = Join-Path $projectRoot "schemas\program-spec.schema.json"

Invoke-ExpectPass -Name "CellMapValid" -Command {
    & $cellMapValidator -Quiet
}
Invoke-ExpectPass -Name "CellObservationsValid" -Command {
    & $cellObservationsValidator -Quiet
}
Invoke-ExpectPass -Name "ControllerInventorySampleValid" -Command {
    & $controllerInventoryValidator -Quiet
}
Invoke-ExpectFail -Name "ControllerInventoryBadFails" -Command {
    & $controllerInventoryValidator -InventoryPath (Join-Path $projectRoot "tests\fixtures\invalid\controller-inventory-bad.psd1") -Quiet
}
Invoke-ExpectPass -Name "ControllerCapabilitySampleSafe" -Command {
    $capability = & $controllerCapabilityTool
    foreach ($property in @(
        "CanCompileTp",
        "CanUploadTp",
        "CanReadTp",
        "CanUseSnpx",
        "CanWriteSnpx",
        "CanUseKarelBridge",
        "CanRunRoboguideEvidence"
    )) {
        if ($capability.$property) {
            throw "Expected public sample capability $property to be false."
        }
    }
    if (-not $capability.RequiresHumanApproval) {
        throw "Expected public sample to require human approval."
    }
}
Invoke-ExpectPass -Name "TemplateCatalogValid" -Command {
    & $templateCatalogValidator -Quiet
}
Invoke-ExpectPass -Name "TemplateCatalogArtifactValid" -Command {
    $catalogPath = Join-Path $projectRoot "generated\test-runs\template-catalog.json"
    & $templateCatalogTool -OutputPath $catalogPath -WriteMarkdown | Out-Null
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    if ([int]$catalog.templateCount -ne 7) {
        throw "Expected template catalog artifact to contain 7 templates."
    }
    $motionTemplates = @($catalog.templates | Where-Object { $_.motionClass -ne "no-motion" })
    if ($motionTemplates.Count -ne 0) {
        throw "Expected current template catalog to remain no-motion only."
    }
}
Invoke-ExpectPass -Name "RoboguideEvidenceConfigValid" -Command {
    & $roboguideEvidenceValidator -Quiet
}
Invoke-ExpectPass -Name "RoboguideEvidencePacketNoMotionValid" -Command {
    $packetPath = Join-Path $projectRoot "generated\test-runs\roboguide-ai-hello.json"
    & $roboguideEvidencePacketTool -SpecPath (Join-Path $projectRoot "examples\AI_HELLO.program-spec.json") -OutputPath $packetPath -WriteMarkdown -Force | Out-Null
    $packet = Get-Content -LiteralPath $packetPath -Raw | ConvertFrom-Json
    if ($packet.evidenceClass -ne "no-motion") {
        throw "Expected AI_HELLO evidence class to be no-motion."
    }
    if ($packet.roboguideRequired) {
        throw "Expected AI_HELLO not to require RoboGuide."
    }
    if ($packet.requiresBeforeAfterSnapshot) {
        throw "Expected AI_HELLO not to require before/after snapshots."
    }
}
Invoke-ExpectPass -Name "RoboguideEvidencePacketIoValid" -Command {
    $packetPath = Join-Path $projectRoot "generated\test-runs\roboguide-ai-iodiag.json"
    & $roboguideEvidencePacketTool -SpecPath (Join-Path $projectRoot "examples\AI_IODIAG.program-spec.json") -OutputPath $packetPath -WriteMarkdown -Force | Out-Null
    $packet = Get-Content -LiteralPath $packetPath -Raw | ConvertFrom-Json
    if ($packet.evidenceClass -ne "io-sequence") {
        throw "Expected AI_IODIAG evidence class to be io-sequence."
    }
    if (-not $packet.roboguideRequired -or -not $packet.requiresBeforeAfterSnapshot) {
        throw "Expected AI_IODIAG to require RoboGuide and before/after snapshots."
    }
    $states = @($packet.expectedWrites.ioSignals | ForEach-Object { "$($_.signal)=$($_.state)" })
    if ($states -notcontains "DO[1]=ON" -or $states -notcontains "DO[1]=OFF") {
        throw "Expected AI_IODIAG packet to include DO[1] ON and OFF writes."
    }
}
Invoke-ExpectPass -Name "InterfaceStrategyValid" -Command {
    & $interfaceStrategyValidator -Quiet
}
Invoke-ExpectPass -Name "InterfaceStrategyArtifactValid" -Command {
    $strategyPath = Join-Path $projectRoot "generated\test-runs\interface-strategy.json"
    & $interfaceStrategyTool -OutputPath $strategyPath -WriteMarkdown | Out-Null
    $strategy = Get-Content -LiteralPath $strategyPath -Raw | ConvertFrom-Json
    $karel = @($strategy.interfaces | Where-Object { $_.Name -eq "karel-tcp-bridge" } | Select-Object -First 1)
    if (-not $karel -or $karel.Enabled) {
        throw "Expected KAREL TCP bridge to exist and remain disabled."
    }
    if ($karel.AllowsProgramRun -or $karel.AllowsRobotMotion -or $karel.AllowsLiveWrites) {
        throw "Expected KAREL TCP bridge to grant no physical command authority yet."
    }
    $writeSchemas = @($strategy.messageSchemas | Where-Object { $_.AllowsWrites })
    if ($writeSchemas.Count -ne 1 -or $writeSchemas[0].Name -ne "command.reviewed-write.request") {
        throw "Expected exactly one proposed reviewed-write request schema."
    }
}
Invoke-ExpectPass -Name "SnpxReadonlyConfigValid" -Command {
    & $snpxReadonlyValidator -Quiet
}
Invoke-ExpectPass -Name "SnpxWriteConfigValid" -Command {
    & $snpxWriteValidator -Quiet
}
Invoke-ExpectPass -Name "SnpxCommissioningMatrixValid" -Command {
    $matrixPath = Join-Path $projectRoot "generated\test-runs\snpx-commissioning-matrix.json"
    & $snpxMatrixTool -OutputPath $matrixPath -WriteMarkdown | Out-Null
    $matrix = Get-Content -LiteralPath $matrixPath -Raw | ConvertFrom-Json
    if ([int]$matrix.summary.collisionCount -ne 0) {
        throw "Expected SNPX commissioning matrix to have no projection collisions."
    }
    if ([int]$matrix.summary.rowCount -ne 14) {
        throw "Expected SNPX commissioning matrix to report 14 rows including probes and read rows."
    }
    if ([int]$matrix.summary.writeAllowedCount -ne 6) {
        throw "Expected SNPX commissioning matrix to report 6 write-allowlisted rows."
    }
    if ([int]$matrix.summary.restorationRequiredCount -ne 1) {
        throw "Expected SNPX commissioning matrix to report 1 restoration-required row."
    }
    $do1 = @($matrix.rows | Where-Object { $_.fanuc -eq "DO[1]" } | Select-Object -First 1)
    if (-not $do1 -or -not $do1.restorationRequired -or $do1.commissioningStatus -ne "read-write-restore-gated") {
        throw "Expected DO[1] matrix row to be restore-gated."
    }
    $r103 = @($matrix.rows | Where-Object { $_.fanuc -eq "R[103]" } | Select-Object -First 1)
    if (-not $r103 -or $r103.writeAllowed -or $r103.commissioningStatus -ne "read-planned") {
        throw "Expected R[103] matrix row to be read-only planned."
    }
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
Invoke-ExpectPass -Name "SnpxIntegerEncodingValid" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\snpx-write-plan-r99-encoding.json"
    & $snpxWritePlanTool -Fanuc "R[99]" -Value 70000 -OutputPath $planPath | Out-Null
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    $words = @($plan.write.encodedWords)
    if ([int]$words[0] -ne 4464 -or [int]$words[1] -ne 1) {
        throw "Expected 70000 to encode as [4464, 1]."
    }
    if ($plan.restoration.required) {
        throw "Expected integer write plan not to require restoration."
    }
}
Invoke-ExpectPass -Name "SnpxBooleanRestorationValid" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\snpx-write-plan-do1-restore.json"
    $evidencePath = Join-Path $projectRoot "generated\test-runs\snpx-live-write-do1-restore.json"
    & $snpxWritePlanTool -Fanuc "DO[1]" -State ON -OutputPath $planPath -Approved | Out-Null
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if (-not $plan.restoration.required) {
        throw "Expected DO[1]=ON plan to require restoration."
    }
    if ($plan.restoration.value -ne "OFF") {
        throw "Expected DO[1]=ON restoration value to be OFF."
    }
    if ($plan.operatorApproval.requiredPhrase -ne "I approve live SNPX write: DO[1]=ON via %R00015") {
        throw "Unexpected required approval phrase."
    }

    $result = & $snpxLiveWriteTool -PlanPath $planPath -OutputPath $evidencePath
    if ($result.Executed) {
        throw "Dry-run SNPX live write plan should not execute."
    }
    if (-not $result.RequiresRestoration) {
        throw "Expected dry-run result to report required restoration."
    }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    if ($evidence.commands.restore.value -ne "OFF") {
        throw "Expected dry-run evidence to include OFF restore command."
    }
}
Invoke-ExpectFail -Name "SnpxLiveWriteRequiresApprovalPhrase" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\snpx-write-plan-do1-approval-gate.json"
    $evidencePath = Join-Path $projectRoot "generated\test-runs\snpx-live-write-do1-approval-gate.json"
    & $snpxWritePlanTool -Fanuc "DO[1]" -State ON -OutputPath $planPath -Approved | Out-Null
    & $snpxLiveWriteTool -PlanPath $planPath -OutputPath $evidencePath -Execute -AcceptLiveWrite | Out-Null
}
Invoke-ExpectFail -Name "SnpxLiveWriteRequiresRestoreSwitch" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\snpx-write-plan-do1-restore-gate.json"
    $evidencePath = Join-Path $projectRoot "generated\test-runs\snpx-live-write-do1-restore-gate.json"
    & $snpxWritePlanTool -Fanuc "DO[1]" -State ON -OutputPath $planPath -Approved | Out-Null
    & $snpxLiveWriteTool -PlanPath $planPath -OutputPath $evidencePath -Execute -AcceptLiveWrite -ApprovalPhrase "I approve live SNPX write: DO[1]=ON via %R00015" | Out-Null
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
    $planRoot = Join-Path $projectRoot "generated\test-runs\cell-status-plan"
    & $statusPlanTool -OutputRoot $planRoot -Force | Out-Null
    $planPath = Join-Path $planRoot "latest\status-plan.json"
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
