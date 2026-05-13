# Workflow

The workflow separates planning, generation, validation, compilation, testing, and deployment.

The default local command is:

```powershell
.\tools\Invoke-FanucLocalWorkflow.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json -Force
```

It performs steps 2 through 7 locally and writes a review packet.

## 1. Plan

Capture the task intent, controller assumptions, safety limits, IO/register use, and expected verification method in a structured spec.

## 2. Validate Spec

Validate the spec against `schemas/program-spec.schema.json`. Treat schema validation as the first gate, not the only gate.

Current local validation:

```powershell
.\tools\Test-FanucJsonSchema.ps1 -JsonPath .\examples\AI_HELLO.program-spec.json -SchemaPath .\schemas\program-spec.schema.json
.\tools\Test-FanucCellMap.ps1
.\tools\Test-FanucProgramSpec.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json
```

`Test-FanucProgramSpec.ps1` enforces `config\cell-map.psd1`, so register writes, IO writes, and future generated `CALL` targets must be explicitly reviewed before LS generation.

## 3. Generate LS

Generate `.LS` from project-owned templates or deterministic emitters. Direct AI-authored `.LS` is allowed only as a draft that still passes the same validators.

Current spec-driven generator:

```powershell
.\tools\New-FanucLsFromSpec.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json -Force
```

The generator writes both `generated/sources/<PROGRAM>.LS` and `generated/jobs/<PROGRAM>/` artifacts.

## 4. Validate LS

Run:

```powershell
.\tools\Test-FanucLsSafety.ps1 -LsPath .\generated\sources\AI_EXAMPLE.LS
```

This checks the prefix, `/PROG` header, filename match, and blocked source patterns.

## 5. Compile

Run:

```powershell
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_EXAMPLE.LS -Force
```

The build script runs LS safety validation before MakeTP.

## 6. Round-Trip

Use PrintTP/readback tooling to decode compiled or robot-downloaded `.TP` files and compare the decoded `.LS` against the generated source.

Current compile/decode round-trip:

```powershell
.\tools\Invoke-FanucTpRoundTrip.ps1 -LsPath .\generated\sources\AI_EXAMPLE.LS -Force
```

This records `decoded.LS` and `roundtrip.json` in `generated/jobs/<PROGRAM>/`.

## 7. Manifest

Collect validation and artifact evidence:

```powershell
.\tools\Update-FanucJobManifest.ps1 -ProgramName AI_EXAMPLE
```

This records `validation.json` and `manifest.json` in `generated/jobs/<PROGRAM>/`. The manifest tracks file hashes, tool paths, validation status, round-trip status, upload status, and human review status.

`localEvidencePassed=true` means the local spec, LS safety, and round-trip gates passed. It does not mean the program is approved for robot upload.

If the spec requires RoboGuide/simulation, `localEvidencePassed` also requires simulation evidence with `status=passed`.

After human review, record the decision:

```powershell
.\tools\Set-FanucJobStatus.ps1 -ProgramName AI_EXAMPLE -HumanReviewStatus approved -Reviewer "Your Name" -HumanReviewNotes "Reviewed generated LS and evidence."
```

Robot-side setup, PR correctness, frame/tool/payload setup, and physical verification are operator-owned and are not tracked as separate manifest gates.

Create a human-readable packet:

```powershell
.\tools\Get-FanucReviewPacket.ps1 -ProgramName AI_EXAMPLE
```

## 8. Simulate

Use RoboGuide for motion, IO, and sequence verification. Record the test conditions and results near the generated artifacts.

## 9. Upload

Upload only after validation and review:

```powershell
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_EXAMPLE.LS -Force -Upload
```

Uploads do not run programs.

For jobs with `generated/jobs/<PROGRAM>/manifest.json`, upload is blocked until `readyForUpload=true`. A successful upload updates the manifest upload status and log path automatically.

After upload, read back and decode the robot copy:

```powershell
.\tools\Invoke-FanucUploadReadback.ps1 -ProgramName AI_EXAMPLE -Force
```

PrintTP expects the TP filename to match the internal program name. The readback tool downloads into `generated/jobs/<PROGRAM>/upload-readback/<PROGRAM>.TP` for that reason.

To list generated AI programs on robot `MD:` without modifying anything:

```powershell
.\tools\Get-FanucRobotDirectory.ps1 -Pattern "AI_*.TP"
```

To reconcile local manifest/readback status against the robot listing:

```powershell
.\tools\Get-FanucJobSummary.ps1 -IncludeRobot
```

If robot FTP is unavailable, the summary still reports local manifest/readback status and marks the robot lookup unavailable.

To save a durable read-only inventory snapshot and reconcile from that snapshot:

```powershell
.\tools\Save-FanucRobotInventory.ps1
.\tools\Get-FanucJobSummary.ps1 -UseLatestRobotInventory
```

To generate the read-only cell status plan:

```powershell
.\tools\Test-FanucCellObservations.ps1
.\tools\New-FanucCellStatusPlan.ps1 -Force
.\tools\New-FanucCellStatusSnapshot.ps1 -Label before-test -Force
```

To decode selected existing non-`AI_` programs for analysis without modifying the robot:

```powershell
.\tools\Invoke-FanucProductionProgramAnalysis.ps1 -FromInventory -Limit 3 -Force
.\tools\Get-FanucProductionAnalysisSummary.ps1 -WriteMarkdown
.\tools\Get-FanucProductionResourceReport.ps1 -WriteMarkdown
```

## 10. Verify

Select and run from the controller only when the operator decides the robot-side setup and path are appropriate. This decision is outside the tracked code-generation gates.
