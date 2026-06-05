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
$motionApplicationValidator = Join-Path $scriptRoot "Test-FanucMotionApplicationSpec.ps1"
$workflowMigrationValidator = Join-Path $scriptRoot "Test-FanucWorkflowMigrationSpec.ps1"
$workflowMigrationReviewPacketTool = Join-Path $scriptRoot "Get-FanucWorkflowMigrationReviewPacket.ps1"
$aMainWorkflowDraftTool = Join-Path $scriptRoot "New-FanucAMainWorkflowDraft.ps1"
$aGreenfieldWorkflowDraftTool = Join-Path $scriptRoot "New-FanucAGreenfieldWorkflowDraft.ps1"
$aMigrationDraftTool = Join-Path $scriptRoot "New-FanucAMigrationDraft.ps1"
$motionLsGenerator = Join-Path $scriptRoot "New-FanucMotionLsFromSpec.ps1"
$motionGeneratedLsValidator = Join-Path $scriptRoot "Test-FanucMotionGeneratedLs.ps1"
$projectPackTool = Join-Path $scriptRoot "New-FanucProjectPack.ps1"
$programGenerator = Join-Path $scriptRoot "New-FanucLsFromSpec.ps1"
$programGeneratorOutputRoot = Join-Path $projectRoot "generated\test-runs\program-spec"
$tpBuildTool = Join-Path $scriptRoot "Invoke-FanucTpBuild.ps1"
$tpRoundTripTool = Join-Path $scriptRoot "Invoke-FanucTpRoundTrip.ps1"
$uploadReadbackTool = Join-Path $scriptRoot "Invoke-FanucUploadReadback.ps1"
$manifestTool = Join-Path $scriptRoot "Update-FanucJobManifest.ps1"
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
$taskStateKarelSourceTool = Join-Path $scriptRoot "New-FanucTaskStateKarelSource.ps1"
$pcdkSnapshotConfigValidator = Join-Path $scriptRoot "Test-FanucPcdkSnapshotConfig.ps1"
$pcdkSnapshotTool = Join-Path $scriptRoot "New-FanucPcdkSnapshot.ps1"
$snpxReadonlyValidator = Join-Path $scriptRoot "Test-FanucSnpxReadonlyConfig.ps1"
$snpxWriteValidator = Join-Path $scriptRoot "Test-FanucSnpxWriteConfig.ps1"
$snpxMatrixTool = Join-Path $scriptRoot "Get-FanucSnpxCommissioningMatrix.ps1"
$snpxSnapshotTool = Join-Path $scriptRoot "Invoke-FanucSnpxReadSnapshot.ps1"
$snpxWritePlanTool = Join-Path $scriptRoot "New-FanucSnpxWritePlan.ps1"
$snpxLiveReadTool = Join-Path $scriptRoot "Invoke-FanucSnpxLiveRead.ps1"
$snpxLiveWriteTool = Join-Path $scriptRoot "Invoke-FanucSnpxLiveWrite.ps1"
$snpxScratchProofTool = Join-Path $scriptRoot "Invoke-FanucSnpxScratchProof.ps1"
$robotServerCommentPlanTool = Join-Path $scriptRoot "New-FanucRobotServerCommentWritePlan.ps1"
$robotServerCommentWriteTool = Join-Path $scriptRoot "Invoke-FanucRobotServerCommentWrite.ps1"
$robotServerAlarmPlanTool = Join-Path $scriptRoot "New-FanucRobotServerAlarmWritePlan.ps1"
$robotServerAlarmWriteTool = Join-Path $scriptRoot "Invoke-FanucRobotServerAlarmWrite.ps1"
$healthCheckTool = Join-Path $scriptRoot "Invoke-FanucProjectHealthCheck.ps1"
$statusPlanTool = Join-Path $scriptRoot "New-FanucCellStatusPlan.ps1"
$statusSnapshotTool = Join-Path $scriptRoot "New-FanucCellStatusSnapshot.ps1"
$statusCompareTool = Join-Path $scriptRoot "Compare-FanucCellStatusSnapshot.ps1"
$simulationEvidenceTool = Join-Path $scriptRoot "Set-FanucSimulationEvidence.ps1"
$autoHomeDraftTool = Join-Path $scriptRoot "New-FanucAutoHomeDraft.ps1"
$schemaPath = Join-Path $projectRoot "schemas\program-spec.schema.json"

Invoke-ExpectPass -Name "CellMapValid" -Command {
    & $cellMapValidator -Quiet
}
Invoke-ExpectPass -Name "CellMapSampleValid" -Command {
    & $cellMapValidator -CellMapPath (Join-Path $projectRoot "config\cell-map.sample.psd1") -Quiet
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
    if ([int]$catalog.templateCount -ne 15) {
        throw "Expected template catalog artifact to contain 15 templates."
    }
    $motionTemplates = @($catalog.templates | Where-Object { $_.motionClass -ne "no-motion" })
    if ($motionTemplates.Count -ne 4) {
        throw "Expected current template catalog to contain four motion templates."
    }
    foreach ($templateId in @("pr-waypoint-sequence-v1", "approach-process-retract-v1", "io-motion-sequence-v1", "motion-action-calc-pr-v1")) {
        if (@($motionTemplates | ForEach-Object { $_.templateId }) -notcontains $templateId) {
            throw "Expected motion template catalog to include $templateId."
        }
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
    if ($packet.roboguideRequired -or -not $packet.operatorRunDecisionOwned -or $packet.requiresBeforeAfterSnapshot) {
        throw "Expected AI_IODIAG evidence to remain optional."
    }
    $states = @($packet.expectedWrites.ioSignals | ForEach-Object { "$($_.signal)=$($_.state)" })
    if ($states -notcontains "DO[1]=ON" -or $states -notcontains "DO[1]=OFF") {
        throw "Expected AI_IODIAG packet to include DO[1] ON and OFF writes."
    }
}
Invoke-ExpectPass -Name "RoboguideEvidencePacketMotionValid" -Command {
    $packetPath = Join-Path $projectRoot "generated\test-runs\roboguide-ai-motion.json"
    & $roboguideEvidencePacketTool -SpecPath (Join-Path $projectRoot "tests\fixtures\valid\AI_MOTION_PR_READY.motion-application.json") -OutputPath $packetPath -WriteMarkdown -Force | Out-Null
    $packet = Get-Content -LiteralPath $packetPath -Raw | ConvertFrom-Json
    if ($packet.evidenceClass -ne "motion") {
        throw "Expected motion application evidence class to be motion."
    }
    if ($packet.specType -ne "motion-application") {
        throw "Expected motion application spec type."
    }
    if ($packet.roboguideRequired -or -not $packet.operatorRunDecisionOwned -or $packet.requiresBeforeAfterSnapshot) {
        throw "Expected motion evidence to remain optional."
    }
    if ([int]$packet.motionResources.userFrame.number -ne 1 -or [int]$packet.motionResources.userTool.number -ne 1 -or [int]$packet.motionResources.payload.number -ne 1) {
        throw "Expected motion packet to include reviewed frame/tool/payload."
    }
    $moves = @($packet.motionPlan.sequence | ForEach-Object { $_.expectedLs })
    foreach ($expected in @("J PR[90] 10% FINE", "L PR[91] 100mm/sec FINE", "L PR[92] 100mm/sec FINE")) {
        if ($moves -notcontains $expected) {
            throw "Motion evidence packet missing expected move: $expected"
        }
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
Invoke-ExpectPass -Name "KarelTcpMessageExamplesValid" -Command {
    $karelSchemaPath = Join-Path $projectRoot "schemas\karel-tcp-message.schema.json"
    foreach ($example in @(
        "examples\karel\status.snapshot.request.json",
        "examples\karel\status.snapshot.response.json",
        "examples\karel\command.reviewed-write.request.json",
        "examples\karel\command.reviewed-write.response.json"
    )) {
        & $schemaValidator -JsonPath (Join-Path $projectRoot $example) -SchemaPath $karelSchemaPath -Quiet
    }
}
Invoke-ExpectPass -Name "KarelTaskStateSourceGenerated" -Command {
    $sourcePath = Join-Path $projectRoot "generated\test-runs\TSKSTATUS.KL"
    $result = & $taskStateKarelSourceTool -ProgramName TSKSTATUS -OutputPath $sourcePath -Force
    if ($result.ProgramName -ne "TSKSTATUS") {
        throw "Unexpected generated KAREL task-state metadata."
    }
    $source = Get-Content -LiteralPath $sourcePath -Raw
    foreach ($expected in @(
        "GET_TPE_PRM(1, data_type",
        "GET_TPE_PRM(2, data_type",
        "GET_TPE_PRM(3, data_type",
        "GET_TSK_INFO(task_name, task_no, TSK_STATUS",
        "SET_INT_REG(reg_no, value, set_status)",
        "IF value_int = PG_RUNNING THEN",
        "CALL TSKSTATUS('TASK_NAME', result_register, display_flag)"
    )) {
        if ($source -notlike "*$expected*") {
            throw "Generated task-state KAREL source missing '$expected'."
        }
    }
}
Invoke-ExpectPass -Name "PcdkSnapshotConfigValid" -Command {
    & $pcdkSnapshotConfigValidator -Quiet
}
Invoke-ExpectPass -Name "PcdkSnapshotExampleSchemaValid" -Command {
    $pcdkSchemaPath = Join-Path $projectRoot "schemas\controller-snapshot.schema.json"
    & $schemaValidator -JsonPath (Join-Path $projectRoot "examples\pcdk\controller-snapshot.plan.json") -SchemaPath $pcdkSchemaPath -Quiet
}
Invoke-ExpectPass -Name "PcdkSnapshotPlanValid" -Command {
    $pcdkSchemaPath = Join-Path $projectRoot "schemas\controller-snapshot.schema.json"
    $snapshotPath = Join-Path $projectRoot "generated\test-runs\pcdk-snapshot-plan.json"
    $result = & $pcdkSnapshotTool -OutputPath $snapshotPath -SkipComProbe
    if ($result.LiveRobotCommandsExecuted) {
        throw "PCDK offline snapshot plan must not execute live robot commands."
    }
    if ($result.ControllerWritesExecuted) {
        throw "PCDK snapshot plan must not execute controller writes."
    }
    & $schemaValidator -JsonPath $snapshotPath -SchemaPath $pcdkSchemaPath -Quiet
    $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
    if ($snapshot.collectionMode -ne "plan") {
        throw "Expected PCDK snapshot default mode to be plan."
    }
    if ($snapshot.connection.requested -or $snapshot.connection.connected) {
        throw "Expected PCDK snapshot plan not to request or establish a controller connection."
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
    if ([int]$matrix.summary.dynamicWriteRangeCount -ne 2) {
        throw "Expected SNPX commissioning matrix to report 2 dynamic write ranges."
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
Invoke-ExpectPass -Name "SnpxDynamicRegisterWritePlanValid" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\snpx-write-plan-r95-dynamic.json"
    & $snpxWritePlanTool -Fanuc "R[95]" -Value 9501 -OutputPath $planPath -Approved | Out-Null
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if ($plan.write.fanuc -ne "R[95]") {
        throw "Expected dynamic SNPX write plan for R[95]."
    }
    if (-not $plan.write.dynamicProjection) {
        throw "Expected R[95] to use dynamic projection."
    }
    if ($plan.write.snpxAddress -ne "%R00079" -or [int]$plan.write.snpxStart -ne 79) {
        throw "Expected R[95] dynamic plan to use %R00079."
    }
    if ($plan.operatorApproval.requiredPhrase -ne "I approve live SNPX write: R[95]=9501 via %R00079 dynamic ASG") {
        throw "Unexpected dynamic R[95] approval phrase."
    }
}
Invoke-ExpectPass -Name "SnpxDynamicOutputWritePlanValid" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\snpx-write-plan-do2-dynamic.json"
    $evidencePath = Join-Path $projectRoot "generated\test-runs\snpx-live-write-do2-dynamic.json"
    & $snpxWritePlanTool -Fanuc "DO[2]" -State ON -OutputPath $planPath -Approved | Out-Null
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if (-not $plan.write.dynamicProjection -or $plan.write.snpxAddress -ne "%R00079") {
        throw "Expected DO[2] to use dynamic projection at %R00079."
    }
    if (-not $plan.restoration.required -or $plan.restoration.value -ne "OFF") {
        throw "Expected DO[2]=ON dynamic plan to require OFF restoration."
    }
    $result = & $snpxLiveWriteTool -PlanPath $planPath -OutputPath $evidencePath
    if ($result.Executed) {
        throw "Dry-run dynamic SNPX live write plan should not execute."
    }
    if (-not $result.DynamicProjection -or [int]$result.Start -ne 79) {
        throw "Expected dry-run dynamic SNPX live write to use start 79."
    }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    if (@($evidence.commands.setasg | Where-Object { $_ -eq "SETASG 79 2 DO[2] 1" }).Count -ne 1) {
        throw "Expected dry-run evidence to include dynamic SETASG for DO[2]."
    }
}
Invoke-ExpectPass -Name "SnpxScratchProofRegisterDryRunValid" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\scratch-proofs-register"
    $result = & $snpxScratchProofTool -Fanuc "R[95]" -Value 9501 -OutputRoot $outputRoot
    if ($result.Executed) {
        throw "Scratch proof register dry-run should not execute."
    }
    if (-not $result.DynamicProjection -or $result.SnpxAddress -ne "%R00079") {
        throw "Expected scratch proof register to use dynamic %R00079 projection."
    }
    if ($result.ApprovalPhrase -ne "I approve live SNPX write: R[95]=9501 via %R00079 dynamic ASG") {
        throw "Unexpected scratch proof R[95] approval phrase."
    }
    if (-not (Test-Path -LiteralPath $result.SummaryPath)) {
        throw "Scratch proof register dry-run did not write summary."
    }
}
Invoke-ExpectPass -Name "SnpxScratchProofOutputDryRunValid" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\scratch-proofs-output"
    $result = & $snpxScratchProofTool -Fanuc "DO[2]" -State ON -OutputRoot $outputRoot
    if ($result.Executed) {
        throw "Scratch proof output dry-run should not execute."
    }
    if (-not $result.RequiresRestoration) {
        throw "Expected scratch proof DO[2]=ON to require restoration."
    }
    if ($result.ApprovalPhrase -ne "I approve live SNPX write: DO[2]=ON via %R00079 dynamic ASG") {
        throw "Unexpected scratch proof DO[2] approval phrase."
    }
    $summary = Get-Content -LiteralPath $result.SummaryPath -Raw | ConvertFrom-Json
    if (-not $summary.restorationRequired) {
        throw "Scratch proof output summary should record restorationRequired=true."
    }
}
Invoke-ExpectFail -Name "SnpxScratchProofRequiresExactApprovalPhrase" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\scratch-proofs-approval"
    & $snpxScratchProofTool -Fanuc "R[95]" -Value 9501 -OutputRoot $outputRoot -Execute -ApprovalPhrase "wrong phrase" | Out-Null
}
Invoke-ExpectFail -Name "SnpxScratchProofRegisterOutsideRangeFails" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\scratch-proofs-r100"
    & $snpxScratchProofTool -Fanuc "R[100]" -Value 100 -OutputRoot $outputRoot | Out-Null
}
Invoke-ExpectFail -Name "SnpxScratchProofOutputOutsideRangeFails" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\scratch-proofs-do81"
    & $snpxScratchProofTool -Fanuc "DO[81]" -State ON -OutputRoot $outputRoot | Out-Null
}
Invoke-ExpectFail -Name "SnpxDynamicRegisterOutsideRangeFails" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\snpx-write-plan-r100-dynamic.json"
    & $snpxWritePlanTool -Fanuc "R[100]" -Value 100 -OutputPath $planPath | Out-Null
}
Invoke-ExpectFail -Name "SnpxDynamicOutputOutsideRangeFails" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\snpx-write-plan-do81-dynamic.json"
    & $snpxWritePlanTool -Fanuc "DO[81]" -State ON -OutputPath $planPath | Out-Null
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
Invoke-ExpectPass -Name "RobotServerCommentPlanFixtureValid" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\robot-server-comment-write-plan-fixture.json"
    $commentMapPath = Join-Path $projectRoot "tests\fixtures\valid\comment-map-approved.psd1"
    $snapshotPath = Join-Path $projectRoot "tests\fixtures\valid\robot-server-metadata.sample.json"
    $result = & $robotServerCommentPlanTool -CommentMapPath $commentMapPath -SnapshotPath $snapshotPath -OutputPath $planPath -Approved
    if ($result.WriteCount -ne 5) {
        throw "Expected fixture comment write plan to include 5 approved writes."
    }
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    if (@($plan.writes | Where-Object { $_.family -eq "GO" }).Count -ne 0) {
        throw "Expected proposed GO row to be skipped."
    }
    if (@($plan.writes | Where-Object { $_.setFunctionCode -in @(2, 4, 5, 15, 16, 17, 18, 67, 68, 69, 70) }).Count -ne 0) {
        throw "Comment write plan included excluded Robot Server function codes."
    }
}
Invoke-ExpectPass -Name "RobotServerCommentWriteDryRunValid" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\robot-server-comment-write-plan-fixture.json"
    $evidencePath = Join-Path $projectRoot "generated\test-runs\robot-server-comment-write-evidence-fixture.json"
    if (-not (Test-Path -LiteralPath $planPath)) {
        $commentMapPath = Join-Path $projectRoot "tests\fixtures\valid\comment-map-approved.psd1"
        $snapshotPath = Join-Path $projectRoot "tests\fixtures\valid\robot-server-metadata.sample.json"
        & $robotServerCommentPlanTool -CommentMapPath $commentMapPath -SnapshotPath $snapshotPath -OutputPath $planPath -Approved | Out-Null
    }
    $result = & $robotServerCommentWriteTool -PlanPath $planPath -OutputPath $evidencePath
    if ($result.Executed) {
        throw "Dry-run Robot Server comment writer should not execute."
    }
    if ($result.WriteCount -ne 5 -or $result.VerifiedCount -ne 0) {
        throw "Unexpected dry-run Robot Server comment writer counts."
    }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    if (@($evidence.rows | Where-Object { $_.before -ne $null -or $_.writeStatusCode -ne $null }).Count -ne 0) {
        throw "Dry-run Robot Server comment writer should not do live readback or writes."
    }
}
Invoke-ExpectPass -Name "RobotServerAlarmPlanFixtureValid" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\robot-server-alarm-write-plan-fixture.json"
    $alarmMapPath = Join-Path $projectRoot "tests\fixtures\valid\alarm-map-approved.psd1"
    $snapshotPath = Join-Path $projectRoot "tests\fixtures\valid\robot-server-alarms.sample.json"
    $result = & $robotServerAlarmPlanTool -AlarmMapPath $alarmMapPath -SnapshotPath $snapshotPath -OutputPath $planPath -Approved
    if ($result.WriteRows -ne 2 -or $result.ChangeCount -ne 3) {
        throw "Expected fixture alarm write plan to include 2 alarm rows and 3 changes."
    }
    $plan = Get-Content -LiteralPath $planPath -Raw | ConvertFrom-Json
    $functionCodes = @()
    foreach ($write in @($plan.writes)) {
        if ($write.messageWrite) {
            $functionCodes += [int]$write.messageWrite.setFunctionCode
        }
        if ($write.severityWrite) {
            $functionCodes += [int]$write.severityWrite.setFunctionCode
        }
    }
    if (@($functionCodes | Where-Object { $_ -notin @(4, 5) }).Count -ne 0) {
        throw "Alarm write plan included non-alarm Robot Server function codes."
    }
    if (@($plan.findings | Where-Object { $_.Rule -eq "AlreadyMatches" }).Count -ne 1) {
        throw "Expected fixture alarm write plan to report one already-matches row."
    }
}
Invoke-ExpectPass -Name "RobotServerAlarmWriteDryRunValid" -Command {
    $planPath = Join-Path $projectRoot "generated\test-runs\robot-server-alarm-write-plan-fixture.json"
    $evidencePath = Join-Path $projectRoot "generated\test-runs\robot-server-alarm-write-evidence-fixture.json"
    if (-not (Test-Path -LiteralPath $planPath)) {
        $alarmMapPath = Join-Path $projectRoot "tests\fixtures\valid\alarm-map-approved.psd1"
        $snapshotPath = Join-Path $projectRoot "tests\fixtures\valid\robot-server-alarms.sample.json"
        & $robotServerAlarmPlanTool -AlarmMapPath $alarmMapPath -SnapshotPath $snapshotPath -OutputPath $planPath -Approved | Out-Null
    }
    $result = & $robotServerAlarmWriteTool -PlanPath $planPath -OutputPath $evidencePath
    if ($result.Executed) {
        throw "Dry-run Robot Server alarm writer should not execute."
    }
    if ($result.WriteRows -ne 2 -or $result.VerifiedCount -ne 0) {
        throw "Unexpected dry-run Robot Server alarm writer counts."
    }
    $evidence = Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
    if (@($evidence.rows | Where-Object { $_.beforeMessage -ne $null -or $_.messageWriteStatusCode -ne $null -or $_.severityWriteStatusCode -ne $null }).Count -ne 0) {
        throw "Dry-run Robot Server alarm writer should not do live readback or writes."
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
Invoke-ExpectPass -Name "ProjectHealthCheckValid" -Command {
    $healthPath = Join-Path $projectRoot "generated\test-runs\health\health-check.json"
    $result = & $healthCheckTool -OutputPath $healthPath -WriteMarkdown
    if (-not $result.OverallPassed) {
        throw "Expected project health check to pass."
    }
    if ($result.LiveRobotCommandsExecuted -or $result.ControllerWritesExecuted) {
        throw "Project health check must remain offline/read-only with respect to the robot."
    }
    $health = Get-Content -LiteralPath $healthPath -Raw | ConvertFrom-Json
    if ($health.liveRobotCommandsExecuted -or $health.controllerWritesExecuted) {
        throw "Health artifact must record no live robot commands and no controller writes."
    }
}
Invoke-ExpectPass -Name "ProjectPackStarterValid" -Command {
    $packPath = Join-Path $projectRoot "generated\test-runs\TestProject"
    $pack = & $projectPackTool -Path $packPath -ProjectName TestProject -WorkcellName "Offline test cell" -Force
    if (-not (Test-Path -LiteralPath $pack.ManifestPath)) {
        throw "Expected project pack manifest to exist."
    }
    $cellMapPath = Join-Path $pack.ProjectPath "config\cell-map.psd1"
    $result = & $motionApplicationValidator -SpecPath $pack.StarterSpecPath -CellMapPath $cellMapPath
    if (-not $result.ReadyForGeneration) {
        throw "Expected starter project-pack motion spec to be generation-ready."
    }
}
Invoke-ExpectPass -Name "SchemaValidSpec" -Command {
    & $schemaValidator -JsonPath (Join-Path $projectRoot "tests\fixtures\valid\AI_VALID.program-spec.json") -SchemaPath $schemaPath -Quiet
}
Invoke-ExpectPass -Name "SpecParameterizedCallPasses" -Command {
    & $specValidator -SpecPath (Join-Path $projectRoot "examples\A_TSKTEST.program-spec.json") -Quiet
}
Invoke-ExpectPass -Name "SpecReviewedRunPasses" -Command {
    & $specValidator -SpecPath (Join-Path $projectRoot "examples\A_TSKRUN.program-spec.json") -Quiet
}
Invoke-ExpectPass -Name "SpecControlFlowPasses" -Command {
    & $specValidator -SpecPath (Join-Path $projectRoot "tests\fixtures\valid\AI_CONTROL.program-spec.json") -Quiet
}
Invoke-ExpectPass -Name "SpecAMainStartupPasses" -Command {
    & $specValidator -SpecPath (Join-Path $projectRoot "examples\applications\A_MAIN.startup.program-spec.json") -Quiet
}
Invoke-ExpectPass -Name "ParameterizedCallGenerator" -Command {
    $result = & $programGenerator -SpecPath (Join-Path $projectRoot "examples\A_TSKTEST.program-spec.json") -OutputRoot $programGeneratorOutputRoot -Force
    $text = Get-Content -LiteralPath $result.SourcePath -Raw
    if ($text -notmatch [regex]::Escape("CALL TSKSTATUS('A_FLEXI_LOADER',91,1) ;")) {
        throw "Expected generated TP caller to include parameterized TSKSTATUS call."
    }
    $compactRemark = "--eg:TSK 200 RUNNING, 204/404 OK START, ELSE NO START ;"
    if ($text -notmatch [regex]::Escape($compactRemark)) {
        throw "Expected generated TSKSTATUS caller to include compact remark: $compactRemark"
    }
    if (@([regex]::Matches($text, [regex]::Escape("--eg:TSK"))).Count -ne 1) {
        throw "Expected generated TSKSTATUS caller to use exactly one compact TSKSTATUS remark."
    }
    if ($text -notmatch [regex]::Escape("DEFAULT_GROUP = *,*,*,*,*,*,*,*;")) {
        throw "Expected no-motion generated TP caller to use wildcard DEFAULT_GROUP."
    }
}
Invoke-ExpectPass -Name "ReviewedRunGenerator" -Command {
    $result = & $programGenerator -SpecPath (Join-Path $projectRoot "examples\A_TSKRUN.program-spec.json") -OutputRoot $programGeneratorOutputRoot -Force
    $text = Get-Content -LiteralPath $result.SourcePath -Raw
    if ($text -notmatch [regex]::Escape("RUN A_TSKDUMMY ;")) {
        throw "Expected generated TP proof to include reviewed RUN A_TSKDUMMY."
    }
    if ($text -notmatch [regex]::Escape("DEFAULT_GROUP = *,*,*,*,*,*,*,*;")) {
        throw "Expected no-motion reviewed RUN proof to use wildcard DEFAULT_GROUP."
    }
    & $lsValidator -LsPath $result.SourcePath -Quiet
}
Invoke-ExpectPass -Name "ControlFlowGenerator" -Command {
    $result = & $programGenerator -SpecPath (Join-Path $projectRoot "tests\fixtures\valid\AI_CONTROL.program-spec.json") -OutputRoot $programGeneratorOutputRoot -Force
    $text = Get-Content -LiteralPath $result.SourcePath -Raw
    foreach ($expected in @(
        "IF (R[90]=100),JMP LBL[100] ;",
        "JMP LBL[900] ;",
        "LBL[100] ;",
        "LBL[999] ;"
    )) {
        if ($text -notmatch [regex]::Escape($expected)) {
            throw "Expected control-flow generated LS to include: $expected"
        }
    }
    & $lsValidator -LsPath $result.SourcePath -Quiet
}
Invoke-ExpectPass -Name "AMainStartupGenerator" -Command {
    $result = & $programGenerator -SpecPath (Join-Path $projectRoot "examples\applications\A_MAIN.startup.program-spec.json") -OutputRoot $programGeneratorOutputRoot -Force
    $text = Get-Content -LiteralPath $result.SourcePath -Raw
    foreach ($expected in @(
        "--eg:TSK 204/404 RUN, ELSE ALARM ;",
        "IF (R[91]=200),JMP LBL[900] ;",
        "IF (R[91]=204),JMP LBL[110] ;",
        "IF (R[91]=404),JMP LBL[110] ;",
        "RUN A_FLEXI_LOADER ;",
        "--eg:TSK 200 RUNNING, ELSE ALARM ;",
        "UALM[90] ;",
        "JMP LBL[999] ;",
        "UALM[91] ;"
    )) {
        if ($text -notmatch [regex]::Escape($expected)) {
            throw "Expected A_MAIN startup generated LS to include: $expected"
        }
    }
    & $lsValidator -LsPath $result.SourcePath -Quiet
}
Invoke-ExpectPass -Name "ManifestLocalEvidenceUploadGate" -Command {
    $result = & $programGenerator -SpecPath (Join-Path $projectRoot "tests\fixtures\valid\AI_CONTROL.program-spec.json") -OutputRoot $programGeneratorOutputRoot -Force
    & $tpRoundTripTool -LsPath $result.SourcePath -Force | Out-Null
    $manifestResult = & $manifestTool -ProgramName AI_CONTROL
    if (-not $manifestResult.LocalEvidencePassed) {
        throw "Expected local evidence to pass for generated AI_CONTROL."
    }
    if (-not $manifestResult.ReadyForUpload) {
        throw "Expected standing commissioning policy to make AI_CONTROL ready for upload after local evidence."
    }
    $manifest = Get-Content -LiteralPath $manifestResult.ManifestPath -Raw | ConvertFrom-Json
    if ($manifest.humanReview.status -eq "approved") {
        throw "Test should not depend on per-job human review approval."
    }
    if ($manifest.commissioningPolicy.uploadGate -ne "local-evidence") {
        throw "Expected manifest to record local-evidence upload gate."
    }
    if ($manifest.gates.readyForUploadReason -notmatch "standing commissioning policy") {
        throw "Expected readyForUploadReason to cite standing commissioning policy."
    }
}
Invoke-ExpectPass -Name "MotionApplicationPlanningSpecValid" -Command {
    $result = & $motionApplicationValidator -SpecPath (Join-Path $projectRoot "examples\applications\AI_APP_PICK_PLACE.motion-application.json")
    if (-not $result.IsValid) {
        throw "Expected motion application planning spec to be valid."
    }
    if ($result.ReadyForGeneration) {
        throw "Planning example should not be ready for generation."
    }
}
Invoke-ExpectPass -Name "WorkflowMigrationPlanningSpecValid" -Command {
    $result = & $workflowMigrationValidator -SpecPath (Join-Path $projectRoot "examples\applications\A_MAIN.workflow-migration.json")
    if (-not $result.IsValid) {
        throw "Expected A_MAIN workflow migration planning spec to be valid."
    }
    if ($result.ReadyForGeneration) {
        throw "A_MAIN workflow migration planning spec should not be ready for generation yet."
    }
    if (@($result.GenerationGateMessages).Count -lt 1) {
        throw "A_MAIN workflow migration spec should expose blocking generation gates."
    }
}
Invoke-ExpectPass -Name "WorkflowMigrationReviewPacketValid" -Command {
    $packet = & $workflowMigrationReviewPacketTool -SpecPath (Join-Path $projectRoot "examples\applications\A_MAIN.workflow-migration.json")
    if ($packet.ReadyForGeneration) {
        throw "A_MAIN review packet should report not ready for generation."
    }
    if ($packet.BlockingDecisionCount -lt 1) {
        throw "A_MAIN review packet should expose blocking decisions."
    }
    if ($packet.Markdown -notmatch "## Blocking Decisions") {
        throw "A_MAIN review packet markdown should include blocking decisions."
    }
}
Invoke-ExpectPass -Name "AMigrationDraftKeepsKarelVisionShallow" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\a-migration"
    $result = & $aMigrationDraftTool -OutputRoot $outputRoot -Force
    $init = @($result.Programs | Where-Object { $_.TargetProgram -eq "A_INIT" } | Select-Object -First 1)
    if (-not $init) {
        throw "Expected migration draft to include A_INIT."
    }
    $initText = Get-Content -LiteralPath $init.SourcePath -Raw
    foreach ($unexpected in @(
        "CALL A_SELECT_VISION(R[100:PART NUMBER]) ;",
        "CALL A_INIT_VISION ;"
    )) {
        if ($initText -match [regex]::Escape($unexpected)) {
            throw "A_INIT must not hide KAREL vision wrapper calls behind another TP frame: $unexpected"
        }
    }
    foreach ($expectedProgram in @("A_SELECT_VISION", "A_INIT_VISION")) {
        $wrapper = @($result.Programs | Where-Object { $_.TargetProgram -eq $expectedProgram } | Select-Object -First 1)
        if (-not $wrapper) {
            throw "Expected migration draft to generate wrapper $expectedProgram."
        }
        $wrapperText = Get-Content -LiteralPath $wrapper.SourcePath -Raw
        if ($wrapperText -notmatch '(?im)^TCD:\s+STACK_SIZE\s*=\s*1000,') {
            throw "$expectedProgram must declare explicit stack size 1000 for KAREL bridge review after INTP-302."
        }
    }

    $placeConveyor = @($result.Programs | Where-Object { $_.TargetProgram -eq "A_PLACE_CONVEYOR" } | Select-Object -First 1)
    $conveyor = @($result.Programs | Where-Object { $_.TargetProgram -eq "A_CONVEYOR" } | Select-Object -First 1)
    if (-not $placeConveyor -or -not $conveyor) {
        throw "Expected migration draft to include conveyor placement/proof programs."
    }
    $placeConveyorText = Get-Content -LiteralPath $placeConveyor.SourcePath -Raw
    foreach ($expected in @(
        "--eg:Call conveyor and require proof before return ;",
        "CALL A_CONVEYOR ;",
        "IF (R[94]=200),JMP LBL[430] ;",
        "LBL[430] ;"
    )) {
        if ($placeConveyorText -notmatch [regex]::Escape($expected)) {
            throw "A_PLACE_CONVEYOR must call A_CONVEYOR synchronously and preserve R94 result: $expected"
        }
    }
    if ($placeConveyorText -match [regex]::Escape("RUN A_CONVEYOR ;")) {
        throw "A_PLACE_CONVEYOR must not RUN A_CONVEYOR and immediately claim success."
    }

    $conveyorText = Get-Content -LiteralPath $conveyor.SourcePath -Raw
    foreach ($expected in @(
        "R[94]=0 ;",
        "R[94]=200 ;",
        "R[94]=408 ;"
    )) {
        if ($conveyorText -notmatch [regex]::Escape($expected)) {
            throw "A_CONVEYOR must report success/timeout through R94: $expected"
        }
    }
}
Invoke-ExpectPass -Name "AMainWorkflowDraftCallRemarks" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\a-main-workflow"
    $result = & $aMainWorkflowDraftTool -OutputRoot $outputRoot -Force
    $mainText = Get-Content -LiteralPath $result.SourcePath -Raw
    foreach ($expected in @(
        "--eg:Main Loop ********************************* ;",
        "--eg:Loop Decision ***************************** ;",
        "--eg:Normal Finish **************************** ;",
        "--eg:Fault Exit ******************************** ;"
    )) {
        if ($mainText -notmatch [regex]::Escape($expected)) {
            throw "A_MAIN workflow draft missing visible flow marker: $expected"
        }
    }
    if ($mainText -notmatch '(?m)^\s+\d+:\s+;\s*$') {
        throw "A_MAIN workflow draft should include blank separator lines for pendant readability."
    }

    foreach ($program in @($result.Programs)) {
        $lines = Get-Content -LiteralPath $program.SourcePath
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -notmatch '^\s*\d+:\s*(?:IF\s*\(.+\),)?CALL\s+') {
                continue
            }

            $j = $i - 1
            while ($j -ge 0 -and $lines[$j] -match '^\s*\d+:\s*;\s*$') {
                $j--
            }

            if ($j -lt 0 -or $lines[$j] -notmatch '^\s*\d+:\s*(--eg:|!)') {
                throw "$($program.ProgramName) has a CALL without an immediate preceding remark: $($lines[$i])"
            }
        }
    }
}
Invoke-ExpectPass -Name "AGreenfieldWorkflowDraftValid" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\a-main-greenfield"
    & $aMigrationDraftTool -OutputRoot $outputRoot -Force | Out-Null
    $result = & $aGreenfieldWorkflowDraftTool -OutputRoot $outputRoot -Force
    $mainText = Get-Content -LiteralPath $result.SourcePath -Raw
    foreach ($expected in @(
        "--eg:Main Loop ********************************* ;",
        "--eg:Loop Decision ***************************** ;",
        "--eg:Status-gated flow: phases own details; R80 200=Run, 204=Work Complete, else Fault; R90 Detail, R94 Step Result ;",
        "--eg:Normal Finish **************************** ;",
        "--eg:Fault Exit ******************************** ;",
        "CALL A_STARTUP ;",
        "CALL A_FEED ;",
        "CALL A_EXCH_CNC ;",
        "CALL A_EXCH_TI ;",
        "CALL A_OUT ;",
        "--eg:Finish Work complete: handshake, keep infeed off ;",
        "CALL A_FINISH_CYCLE ;",
        "--eg:Return robot to home before normal program end ;",
        "CALL A_GO_HOME ;"
    )) {
        if ($mainText -notmatch [regex]::Escape($expected)) {
            throw "A_MAIN greenfield draft missing expected flow text: $expected"
        }
    }
    if ($mainText -notmatch '(?m)^\s+\d+:\s+;\s*$') {
        throw "A_MAIN greenfield draft should include blank separator lines for pendant readability."
    }
    if ($mainText -match [regex]::Escape("CALL A_BOOT ;")) {
        throw "A_MAIN greenfield draft should use A_STARTUP vocabulary, not A_BOOT."
    }
    if ($mainText -match "Drained|drained") {
        throw "A_MAIN greenfield draft should use Finish Work vocabulary instead of drained/drain pendant wording."
    }
    if (-not @($result.Programs | Where-Object { $_.ProgramName -eq "A_STARTUP" })) {
        throw "Expected greenfield draft to include A_STARTUP."
    }
    foreach ($stackProgramName in @("A_MAIN", "A_STARTUP", "A_FSTART", "A_FLEXI_LOADER", "A_FLX_SCAN")) {
        $stackProgram = @($result.Programs | Where-Object { $_.ProgramName -eq $stackProgramName } | Select-Object -First 1)
        if (-not $stackProgram) {
            throw "Expected greenfield draft to include $stackProgramName."
        }
        $stackText = Get-Content -LiteralPath $stackProgram.SourcePath -Raw
        if ($stackText -notmatch '(?im)^TCD:\s+STACK_SIZE\s*=\s*1000,') {
            throw "$stackProgramName must declare stack size 1000 for KAREL-dependent entry chain review after INTP-302."
        }
    }

    $startup = @($result.Programs | Where-Object { $_.ProgramName -eq "A_STARTUP" } | Select-Object -First 1)
    if (-not $startup) {
        throw "Expected greenfield draft to include A_STARTUP."
    }
    $startupText = Get-Content -LiteralPath $startup.SourcePath -Raw
    foreach ($expected in @(
        "--eg:Recipe must be valid with no apply pending ;",
        "IF (F[68:OFF] OR !F[69:OFF]),JMP LBL[495] ;",
        "MESSAGE[RECIPE NOT READY] ;",
        "UALM[4] ;",
        "--eg:Robot must be at perch before startup ;",
        "IF (!UO[7:OFF:At perch]),JMP LBL[496] ;",
        "MESSAGE[ROBOT NOT HOME] ;",
        "UALM[5] ;",
        "--eg:Initialize non-WIP state; do not erase transfer flags F61-F65 ;",
        "CALL A_INIT_STATE ;",
        "--eg:Select vision at startup level to keep bridge stack shallow ;",
        "CALL A_SELECT_VISION(R[100:PART NUMBER]) ;",
        "--eg:Initialize vision bridge at the same shallow caller level ;",
        "CALL A_INIT_VISION ;"
    )) {
        if ($startupText -notmatch [regex]::Escape($expected)) {
            throw "A_STARTUP missing expected startup guard semantics: $expected"
        }
    }
    foreach ($unexpected in @(
        "MESSAGE[HOME CHECK FAIL] ;",
        "MESSAGE[PERCH CHECK FAIL] ;"
    )) {
        if ($startupText -match [regex]::Escape($unexpected)) {
            throw "A_STARTUP should not emit stale generic startup message: $unexpected"
        }
    }
    if ($startupText -match 'CALL\s+A_INIT\s*;') {
        throw "A_STARTUP must not call migrated A_INIT because it clears transfer WIP flags."
    }

    $initState = @($result.Programs | Where-Object { $_.ProgramName -eq "A_INIT_STATE" } | Select-Object -First 1)
    if (-not $initState) {
        throw "Expected greenfield draft to include A_INIT_STATE."
    }
    $initStateText = Get-Content -LiteralPath $initState.SourcePath -Raw
    foreach ($expected in @(
        "--eg:Skip vacuum reset when robot-held WIP may still be gripped ;",
        "IF (F[59:OFF] OR F[61:OFF:PART_4_CNC] OR F[63:OFF:PART_4_INS] OR F[65:OFF:PART_2_PRINT]),JMP LBL[100] ;",
        "--eg:No robot-held WIP: reset vacuum hold outputs ;",
        "--eg:Reset non-holding feeder/conveyor outputs ;"
    )) {
        if ($initStateText -notmatch [regex]::Escape($expected)) {
            throw "A_INIT_STATE missing physical WIP preservation guard: $expected"
        }
    }
    foreach ($forbiddenWipClear in @(
        "F[61:OFF:PART_4_CNC]=(OFF) ;",
        "F[63:OFF:PART_4_INS]=(OFF) ;",
        "F[65:OFF:PART_2_PRINT]=(OFF) ;"
    )) {
        if ($initStateText -match [regex]::Escape($forbiddenWipClear)) {
            throw "A_INIT_STATE must preserve transfer WIP and not emit: $forbiddenWipClear"
        }
    }

    $feedPick = @($result.Programs | Where-Object { $_.ProgramName -eq "A_FEED_PICK" } | Select-Object -First 1)
    $feedOrient = @($result.Programs | Where-Object { $_.ProgramName -eq "A_FEED_ORIENT" } | Select-Object -First 1)
    if (-not $feedPick -or -not $feedOrient) {
        throw "Expected greenfield feed split to include A_FEED_PICK and A_FEED_ORIENT."
    }
    $feedPickText = Get-Content -LiteralPath $feedPick.SourcePath -Raw
    $feedOrientText = Get-Content -LiteralPath $feedOrient.SourcePath -Raw
    if ($feedPickText -match [regex]::Escape("F[61:OFF:PART_4_CNC]=(ON) ;")) {
        throw "A_FEED_PICK must not claim F61 before optional orientation is proven."
    }
    if ($feedPickText -notmatch [regex]::Escape("F[59:OFF]=(ON) ;")) {
        throw "A_FEED_PICK must claim intermediate F59 picked WIP before another abort/restart point."
    }
    if ($feedOrientText -notmatch [regex]::Escape("F[59:OFF]=(OFF) ;")) {
        throw "A_FEED_ORIENT must clear intermediate F59 picked WIP after orientation is resolved."
    }
    if ($feedOrientText -notmatch [regex]::Escape("F[61:OFF:PART_4_CNC]=(ON) ;")) {
        throw "A_FEED_ORIENT must claim F61 after optional orientation succeeds or is skipped."
    }

    foreach ($expectedProgram in @("A_FLEXI_LOADER", "A_FLX_SCAN", "A_FLX_RETRY")) {
        if (-not @($result.Programs | Where-Object { $_.ProgramName -eq $expectedProgram })) {
            throw "Expected greenfield Flexi Loader split to include $expectedProgram."
        }
    }
    $flexiLoader = @($result.Programs | Where-Object { $_.ProgramName -eq "A_FLEXI_LOADER" } | Select-Object -First 1)
    $flexiLoaderText = Get-Content -LiteralPath $flexiLoader.SourcePath -Raw
    foreach ($expected in @(
        "CALL TSKSTATUS('A_MAIN',92,0) ;",
        "CALL A_FLX_SCAN ;",
        "CALL K_VS_CLOSE ;"
    )) {
        if ($flexiLoaderText -notmatch [regex]::Escape($expected)) {
            throw "A_FLEXI_LOADER missing readable async owner step: $expected"
        }
    }
    if ($flexiLoaderText -match [regex]::Escape("CALL K_VS_SENDCMD('TRG') ;")) {
        throw "A_FLEXI_LOADER should not inline vision trigger logic; use A_FLX_SCAN."
    }

    $flexiScan = @($result.Programs | Where-Object { $_.ProgramName -eq "A_FLX_SCAN" } | Select-Object -First 1)
    $flexiScanText = Get-Content -LiteralPath $flexiScan.SourcePath -Raw
    foreach ($expected in @(
        "CALL K_VS_SENDCMD('TRG') ;",
        "CALL K_VS_WAITCMD('TRG',50) ;",
        "CALL K_VS_RECVVAL(30) ;",
        "CALL A_FLX_RETRY ;"
    )) {
        if ($flexiScanText -notmatch [regex]::Escape($expected)) {
            throw "A_FLX_SCAN missing expected scan/retry step: $expected"
        }
    }

    $manifestPath = Join-Path $outputRoot "a-main-active-greenfield.json"
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    foreach ($expectedDependency in @(
        "A_CONVEYOR",
        "A_FEEDER",
        "A_SHAKE_RATTLE_N_ROLL",
        "A_PUSHER1",
        "A_OPENG1",
        "A_OPENG2",
        "A_PUSHER2",
        "K_VS_CONNECT",
        "K_VS_SENDCMD",
        "K_VS_WAITCMD",
        "K_VS_RECVVAL",
        "K_VS_CLOSE",
        "TSKSTATUS"
    )) {
        if (-not @($manifest.dependencyPrograms | Where-Object { $_.ProgramName -eq $expectedDependency })) {
            throw "A_MAIN greenfield manifest missing recursive dependency: $expectedDependency"
        }
    }
    foreach ($unexpectedDependency in @("CNC", "TI", "conveyor", "fault")) {
        if (@($manifest.dependencyPrograms | Where-Object { $_.ProgramName -eq $unexpectedDependency })) {
            throw "A_MAIN greenfield manifest should not derive dependencies from prose remarks: $unexpectedDependency"
        }
    }

    $outfeed = @($result.Programs | Where-Object { $_.ProgramName -eq "A_OUT" } | Select-Object -First 1)
    if (-not $outfeed) {
        throw "Expected greenfield draft to include A_OUT."
    }
    $outText = Get-Content -LiteralPath $outfeed.SourcePath -Raw
    if ($outText -match [regex]::Escape("CALL A_CONV_DROP ;")) {
        throw "A_OUT must not call A_CONV_DROP because that wrapper clears F[65] internally."
    }
    foreach ($expected in @(
        "CALL A_RGP_CVY ;",
        "CALL A_PLACE_CONVEYOR ;",
        "F[65:OFF:PART_2_PRINT]=(OFF) ;"
    )) {
        if ($outText -notmatch [regex]::Escape($expected)) {
            throw "A_OUT missing expected outfeed ownership text: $expected"
        }
    }

    foreach ($program in @($result.Programs)) {
        & $lsValidator -LsPath $program.SourcePath -Quiet
        $rawText = [System.IO.File]::ReadAllText($program.SourcePath)
        if (-not $rawText.EndsWith("`r`n")) {
            throw "$($program.ProgramName) greenfield draft must end with CRLF for MakeTP compatibility."
        }
        if ($rawText -match "(?<!`r)`n") {
            throw "$($program.ProgramName) greenfield draft contains LF-only line endings; MakeTP may reject it."
        }
        $lines = Get-Content -LiteralPath $program.SourcePath
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '\$WAITTMOUT\s*=') {
                if ($i + 1 -ge $lines.Count -or $lines[$i + 1] -notmatch '\bWAIT\b.+\bTIMEOUT\b') {
                    throw "$($program.ProgramName) sets `$WAITTMOUT without the timed WAIT on the next line: $($lines[$i])"
                }
            }

            if ($lines[$i] -notmatch '^\s*\d+:\s*CALL\s+') {
                continue
            }

            $j = $i - 1
            while ($j -ge 0 -and $lines[$j] -match '^\s*\d+:\s*;\s*$') {
                $j--
            }

            if ($j -lt 0 -or $lines[$j] -notmatch '^\s*\d+:\s*(--eg:|!)') {
                throw "$($program.ProgramName) has a CALL without an immediate preceding remark: $($lines[$i])"
            }
        }

        if ($rawText -match '--eg:ERR ' -and $rawText -notmatch [regex]::Escape("--eg:Error Section *************************** ;")) {
            throw "$($program.ProgramName) has error labels without an Error Section marker."
        }
        if ($rawText -match 'LBL\[999\] ;' -and $rawText -notmatch [regex]::Escape("--eg:Program End ***************************** ;")) {
            throw "$($program.ProgramName) has LBL[999] without a Program End marker."
        }
    }
}
Invoke-ExpectFail -Name "MotionApplicationBadGenerationFails" -Command {
    & $motionApplicationValidator -SpecPath (Join-Path $projectRoot "tests\fixtures\invalid\AI_APP_BAD.motion-application.json") -Quiet
}
Invoke-ExpectPass -Name "MotionApplicationReadyFixtureValid" -Command {
    $result = & $motionApplicationValidator -SpecPath (Join-Path $projectRoot "tests\fixtures\valid\AI_MOTION_PR_READY.motion-application.json")
    if (-not $result.ReadyForGeneration) {
        throw "Expected motion fixture to be ready for generation."
    }
}
Invoke-ExpectPass -Name "MotionApplicationPr300Valid" -Command {
    $result = & $motionApplicationValidator -SpecPath (Join-Path $projectRoot "examples\applications\AI_PR300_PATH.motion-application.json")
    if (-not $result.ReadyForGeneration) {
        throw "Expected PR300 local application spec to be ready for offline generation."
    }
}
Invoke-ExpectPass -Name "MotionApplicationAprValid" -Command {
    $result = & $motionApplicationValidator -SpecPath (Join-Path $projectRoot "examples\applications\AI_APR_PATH.motion-application.json")
    if (-not $result.ReadyForGeneration) {
        throw "Expected APR application spec to be ready for offline generation."
    }
}
Invoke-ExpectPass -Name "MotionApplicationIoPathValid" -Command {
    $result = & $motionApplicationValidator -SpecPath (Join-Path $projectRoot "examples\applications\AI_IOPATH.motion-application.json")
    if (-not $result.ReadyForGeneration) {
        throw "Expected IO motion application spec to be ready for offline generation."
    }
}
Invoke-ExpectPass -Name "MotionActionCalcPrValid" -Command {
    $result = & $motionApplicationValidator -SpecPath (Join-Path $projectRoot "tests\fixtures\valid\AI_MOTION_ACTION_CALC_PR.motion-application.json")
    if (-not $result.ReadyForGeneration) {
        throw "Expected motion-action calculated PR fixture to be ready for offline generation."
    }
}
Invoke-ExpectPass -Name "MotionPrWaypointGenerator" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\motion"
    $result = & $motionLsGenerator -SpecPath (Join-Path $projectRoot "tests\fixtures\valid\AI_MOTION_PR_READY.motion-application.json") -OutputRoot $outputRoot -Force
    if ($result.ControllerWritesExecuted -or $result.LiveRobotCommandsExecuted) {
        throw "Motion LS generator must remain offline."
    }
    $text = Get-Content -LiteralPath $result.SourcePath -Raw
    foreach ($expected in @("UFRAME_NUM=1", "UTOOL_NUM=1", "J PR[90] 10% FINE", "L PR[91] 100mm/sec FINE", "L PR[92] 100mm/sec FINE")) {
        if ($text -notmatch [regex]::Escape($expected)) {
            throw "Generated motion LS missing expected text: $expected"
        }
    }
    if ($text -match '(?m)^\s*P\[') {
        throw "First motion generator should not emit taught-position records."
    }
}
Invoke-ExpectPass -Name "MotionGeneratedLsMatchesSpec" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\motion"
    $result = & $motionLsGenerator -SpecPath (Join-Path $projectRoot "tests\fixtures\valid\AI_MOTION_PR_READY.motion-application.json") -OutputRoot $outputRoot -Force
    $validation = & $motionGeneratedLsValidator -SpecPath (Join-Path $projectRoot "tests\fixtures\valid\AI_MOTION_PR_READY.motion-application.json") -LsPath $result.SourcePath
    if (-not $validation.IsValid) {
        throw "Expected generated motion LS to match its motion application spec."
    }
}
Invoke-ExpectPass -Name "MotionIoGeneratedLsMatchesSpec" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\motion-io"
    $result = & $motionLsGenerator -SpecPath (Join-Path $projectRoot "examples\applications\AI_IOPATH.motion-application.json") -OutputRoot $outputRoot -Force
    $validation = & $motionGeneratedLsValidator -SpecPath (Join-Path $projectRoot "examples\applications\AI_IOPATH.motion-application.json") -LsPath $result.SourcePath
    if (-not $validation.IsValid) {
        throw "Expected generated IO motion LS to match its motion application spec."
    }
    $text = Get-Content -LiteralPath $result.SourcePath -Raw
    foreach ($expected in @("DO[2]=ON", "DO[2]=OFF")) {
        if ($text -notmatch [regex]::Escape($expected)) {
            throw "Generated IO motion LS missing expected text: $expected"
        }
    }
}
Invoke-ExpectPass -Name "MotionActionCalcPrGeneratedLsMatchesSpec" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\motion-action-calc-pr"
    $specPath = Join-Path $projectRoot "tests\fixtures\valid\AI_MOTION_ACTION_CALC_PR.motion-application.json"
    $result = & $motionLsGenerator -SpecPath $specPath -OutputRoot $outputRoot -Force
    $validation = & $motionGeneratedLsValidator -SpecPath $specPath -LsPath $result.SourcePath
    if (-not $validation.IsValid) {
        throw "Expected generated motion-action calculated PR LS to match its motion application spec."
    }
    $text = Get-Content -LiteralPath $result.SourcePath -Raw
    foreach ($expected in @("CALL A_CALC_POS", "J PR[21] 10% FINE", "R[95]=21", "L PR[20] 100mm/sec FINE", "R[95]=20", "L PR[22] 100mm/sec FINE", "R[95]=22")) {
        if ($text -notmatch [regex]::Escape($expected)) {
            throw "Generated motion-action calculated PR LS missing expected text: $expected"
        }
    }
    $frameSetCount = ([regex]::Matches($text, "UFRAME_NUM=1")).Count
    $toolSetCount = ([regex]::Matches($text, "UTOOL_NUM=1")).Count
    if ($frameSetCount -lt 3 -or $toolSetCount -lt 3) {
        throw "Generated motion-action calculated PR LS must repeat UFRAME/UTOOL before each motion."
    }
    if ($text -match "Offset,PR|Tool_Offset,PR") {
        throw "Generated motion-action calculated PR LS must not emit inline offset modifiers by default."
    }
}
Invoke-ExpectPass -Name "UploadRequiresFreshReadbackAndManifest" -Command {
    $buildText = Get-Content -LiteralPath $tpBuildTool -Raw
    foreach ($expected in @(
        "Invoke-FanucUploadReadback.ps1",
        "-ProgramName `$programName",
        "-OutputRoot `$resolvedOutputRoot",
        "HashMatch",
        "DecodeSucceeded",
        "Update-FanucJobManifest.ps1"
    )) {
        if ($buildText -notmatch [regex]::Escape($expected)) {
            throw "Invoke-FanucTpBuild upload path missing mandatory evidence step: $expected"
        }
    }

    $readbackText = Get-Content -LiteralPath $uploadReadbackTool -Raw
    if ($readbackText -notmatch [regex]::Escape('[string]$OutputRoot = "generated"')) {
        throw "Invoke-FanucUploadReadback must accept OutputRoot so build/readback use the same job tree."
    }
    if ($readbackText -notmatch 'throw "Robot readback TP hash matched local compiled TP, but PrintTP could not decode') {
        throw "Invoke-FanucUploadReadback must fail loudly when readback decode fails."
    }
}
Invoke-ExpectPass -Name "AutoHomeLinearRecoveryGenerated" -Command {
    $outputRoot = Join-Path $projectRoot "generated\test-runs\auto-home"
    $result = & $autoHomeDraftTool -OutputRoot $outputRoot -Force
    $text = Get-Content -LiteralPath $result.AutoHomePath -Raw

    foreach ($expected in @(
        "L PR[11:B_PICK_APP] 50mm/sec FINE",
        "L PR[21:RG_PLACE_APP] 50mm/sec FINE",
        "L PR[31:RG_PICK_APP] 10mm/sec FINE",
        "J PR[1:JHOME] 10% FINE"
    )) {
        if ($text -notmatch [regex]::Escape($expected)) {
            throw "Auto-home generated source missing expected recovery motion: $expected"
        }
    }

    foreach ($unexpected in @(
        "J PR[11:B_PICK_APP] 10% FINE",
        "J PR[21:RG_PLACE_APP] 10% FINE",
        "J PR[31:RG_PICK_APP] 10% FINE"
    )) {
        if ($text -match [regex]::Escape($unexpected)) {
            throw "Auto-home generated source converted reviewed linear recovery to joint motion: $unexpected"
        }
    }

    $map = Get-Content -LiteralPath $result.MapPath -Raw | ConvertFrom-Json
    $linearTargets = @($map.linearRecoveryTargets)
    if (-not @($linearTargets | Where-Object { [int]$_.PositionRegister -eq 11 -and $_.RecoverySpeed -eq "50mm/sec" })) {
        throw "Auto-home map must record PR[11] linear recovery speed evidence."
    }
}
Invoke-ExpectPass -Name "MotionSimulationEvidenceNotesOnly" -Command {
    $packetPath = Join-Path $projectRoot "generated\test-runs\roboguide-ai-motion.json"
    if (-not (Test-Path -LiteralPath $packetPath)) {
        & $roboguideEvidencePacketTool -SpecPath (Join-Path $projectRoot "tests\fixtures\valid\AI_MOTION_PR_READY.motion-application.json") -OutputPath $packetPath -WriteMarkdown -Force | Out-Null
    }
    $result = & $simulationEvidenceTool `
        -ProgramName AI_SIMCHK `
        -Status passed `
        -MotionInvolved $true `
        -WorkcellPath "fixture-workcell" `
        -EvidencePacketPath $packetPath `
        -Reviewer "offline-test" `
        -Notes "Offline fixture evidence shape only; motion resource correctness is operator-owned."
    $record = Get-Content -LiteralPath $result.EvidencePath -Raw | ConvertFrom-Json
    if ($record.status -ne "passed" -or -not [bool]$record.motionInvolved) {
        throw "Expected motion simulation evidence to record passed motion status."
    }
}
Invoke-ExpectPass -Name "SpecScratchRangePasses" -Command {
    $specPath = Join-Path $projectRoot "generated\test-runs\AI_RANGE_OK.program-spec.json"
    @'
{
  "programName": "AI_RANGE_OK",
  "intent": "Validate approved scratch write ranges.",
  "safety": {
    "motionAllowed": false,
    "requiresHumanReview": true
  },
  "operations": [
    {
      "type": "registerWrite",
      "register": 95,
      "value": 123
    },
    {
      "type": "ioWrite",
      "signal": "DO[80]",
      "state": true
    }
  ]
}
'@ | Set-Content -LiteralPath $specPath -Encoding ASCII
    & $specValidator -SpecPath $specPath -Quiet
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
Invoke-ExpectFail -Name "SpecScratchRangeStopsAtBoundary" -Command {
    $specPath = Join-Path $projectRoot "generated\test-runs\AI_RANGE_BAD.program-spec.json"
    @'
{
  "programName": "AI_RANGE_BAD",
  "intent": "Validate scratch write range boundary.",
  "safety": {
    "motionAllowed": false,
    "requiresHumanReview": true
  },
  "operations": [
    {
      "type": "registerWrite",
      "register": 100,
      "value": 123
    },
    {
      "type": "ioWrite",
      "signal": "DO[81]",
      "state": true
    }
  ]
}
'@ | Set-Content -LiteralPath $specPath -Encoding ASCII
    & $specValidator -SpecPath $specPath -Quiet
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
Invoke-ExpectFail -Name "LsPrCalculationWildcardFails" -Command {
    & $lsValidator -LsPath (Join-Path $projectRoot "tests\fixtures\invalid\AI_PR_CALC_WILDCARD.LS") -Quiet
}
Invoke-ExpectFail -Name "LsGroupedNegationFails" -Command {
    & $lsValidator -LsPath (Join-Path $projectRoot "tests\fixtures\invalid\AI_GROUPED_NEGATION.LS") -Quiet
}

$failed = @($tests | Where-Object { -not $_.Passed })
$tests
if ($failed.Count -gt 0) {
    $failedMessages = $failed | ForEach-Object { "- $($_.Name): $($_.Message)" }
    throw "$($failed.Count) tool test(s) failed:`n$($failedMessages -join "`n")"
}
