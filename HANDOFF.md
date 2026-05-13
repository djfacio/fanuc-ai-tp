# Handoff

Start here in a fresh Codex session.

## What Works

- Robot FTP is reachable at `192.168.5.10:21`.
- Login works with `anonymous` / `guest`.
- WinOLPC MakeTP is installed and compiles for `V9.40-1`.
- `AI_HELLO.TP` has been compiled, uploaded, selected on the pendant, and executed cleanly.

## Primary Commands

Open PowerShell in this folder:

```powershell
cd <path-to-this-repo>\fanuc-ai-tp
```

Run the full local workflow:

```powershell
.\tools\Invoke-FanucLocalWorkflow.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json -Force
```

Manual steps:

Validate the example spec:

```powershell
.\tools\Test-FanucProgramSpec.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json
```

Generate LS from the spec:

```powershell
.\tools\New-FanucLsFromSpec.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json -Force
```

Validate LS:

```powershell
.\tools\Test-FanucLsSafety.ps1 -LsPath .\generated\sources\AI_HELLO.LS
```

Compile only:

```powershell
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_HELLO.LS -Force
```

Round-trip compile/decode evidence:

```powershell
.\tools\Invoke-FanucTpRoundTrip.ps1 -LsPath .\generated\sources\AI_HELLO.LS -Force
```

Record simulation evidence:

```powershell
.\tools\Set-FanucSimulationEvidence.ps1 -ProgramName AI_HELLO -Status not-required -Notes "No-motion workflow."
```

Update job manifest:

```powershell
.\tools\Update-FanucJobManifest.ps1 -ProgramName AI_HELLO
```

Generate review packet:

```powershell
.\tools\Get-FanucReviewPacket.ps1 -ProgramName AI_HELLO
```

Record review only after manual inspection:

```powershell
.\tools\Set-FanucJobStatus.ps1 -ProgramName AI_HELLO -HumanReviewStatus approved -Reviewer "Your Name" -HumanReviewNotes "Reviewed generated LS and local evidence."
```

Compile and upload to robot `MD:`:

```powershell
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_HELLO.LS -Force -Upload
```

## Next Good Step

Phase 1 is closed. See `docs\PHASE_1_SUMMARY.md`.

Phase 2 has started as a disabled KAREL/TCP bridge contract and richer status-planning track. See `docs\PHASE_2_PLAN.md`. KAREL bridge work is schema/examples only right now; do not deploy robot-resident KAREL or grant command authority without a separate review.

PCDK is now a first-class read-only evidence track, not a generation or command path. See `docs\PCDK_STRATEGY.md`, `config\pcdk-snapshot.psd1`, `schemas\controller-snapshot.schema.json`, and `tools\New-FanucPcdkSnapshot.ps1`. The default PCDK command is offline plan mode:

```powershell
.\tools\Test-FanucPcdkSnapshotConfig.ps1
.\tools\New-FanucPcdkSnapshot.ps1
```

Use `-ConnectReadOnly` only when a live controller read is intentionally in scope. The first PCDK track must record `controllerWritesExecuted=false` and must not use task control, program selection, IO writes, FTP upload/delete, frame updates, position record/update, or move-to behavior.

The real application workflow, including future motion, now starts with `docs\REAL_APPLICATION_WORKFLOW.md`, `schemas\motion-application-spec.schema.json`, and `tools\Test-FanucMotionApplicationSpec.ps1`. The current example is planning-only and intentionally not generation-ready:

```powershell
.\tools\Test-FanucMotionApplicationSpec.ps1 -SpecPath .\examples\applications\AI_APP_PICK_PLACE.motion-application.json
```

Run the project health check before new work:

```powershell
.\tools\Invoke-FanucProjectHealthCheck.ps1 -WriteMarkdown
```

Continue building spec-driven generators around constrained templates, starting with no-motion diagnostics and simple IO/register utilities. Keep motion generation behind explicit review and manual verification. Use `docs\STRATEGY.md`, `docs\SAFETY.md`, `docs\WORKFLOW.md`, and `schemas\program-spec.schema.json` as the starting architecture.

The deterministic no-motion template catalog is now explicit in `config\template-catalog.psd1`. Validate it with `tools\Test-FanucTemplateCatalog.ps1` and emit review artifacts with `tools\Get-FanucTemplateCatalog.ps1 -WriteMarkdown`.

RoboGuide/manual evidence packet generation is available for specs:

```powershell
.\tools\Test-FanucRoboguideEvidenceConfig.ps1
.\tools\New-FanucRoboguideEvidencePacket.ps1 -SpecPath .\examples\AI_IODIAG.program-spec.json -WriteMarkdown -Force
```

Interface strategy is explicit in `config\interface-strategy.psd1`. KAREL TCP is documented as a future disabled bridge, not an active command path:

```powershell
.\tools\Test-FanucInterfaceStrategy.ps1
.\tools\Get-FanucInterfaceStrategy.ps1 -WriteMarkdown
```

Phase 2 KAREL/TCP schema examples now exist under:

```text
schemas\karel-tcp-message.schema.json
examples\karel\
```

The latest proven local evidence is in `generated\jobs\AI_HELLO\manifest.json`. It records spec validation, LS safety, MakeTP compile, PrintTP decode, matching normalized `/MN` instructions, and file hashes. `localEvidencePassed` is true; `readyForUpload` stays false until human review/upload policy is explicitly recorded.

`Invoke-FanucTpBuild.ps1 -Upload` now blocks manifest-backed jobs unless `readyForUpload=true`; successful uploads update manifest upload status automatically.

## Current Generated Job Status

As of the latest manifest summary, these jobs have local evidence passed, human review approved, upload recorded, robot readback hash/decode passed, and pendant verification passed:

- `AI_HELLO`
- `AI_REGDIAG`
- `AI_PRCHECK`
- `AI_FRMTOOL`
- `AI_IODIAG`
- `AI_SNAPSHOT`
- `AI_CELLCHK`

The latest robot directory check connected to `192.168.5.10` and confirmed the generated `AI_*.TP` files are present on robot `MD:`. `Get-FanucJobSummary.ps1 -IncludeRobot` reports `RobotLookupStatus=ok` and `RobotFilePresent=True` for the uploaded jobs.

After upload, run:

```powershell
.\tools\Invoke-FanucUploadReadback.ps1 -ProgramName AI_HELLO -Force
```

Then refresh the manifest.

To check what generated programs are actually present on robot `MD:`:

```powershell
.\tools\Get-FanucRobotDirectory.ps1 -Pattern "AI_*.TP"
```

To see all local jobs with review, upload, readback, pendant, and optional robot-presence status:

```powershell
.\tools\Get-FanucJobSummary.ps1
.\tools\Get-FanucJobSummary.ps1 -IncludeRobot
```

To capture a durable read-only robot inventory and compare against it later:

```powershell
.\tools\Save-FanucRobotInventory.ps1
.\tools\Get-FanucJobSummary.ps1 -UseLatestRobotInventory
```

Latest inventory snapshot captured 474 parsed `MD:` entries at `generated\robot-inventory\latest.json`.

Controlled production analysis has been proven read-only with:

```powershell
.\tools\Invoke-FanucProductionProgramAnalysis.ps1 -FromInventory -Limit 3 -Force
```

The latest broader run decoded 25 non-`AI_` TP programs into `generated\production-analysis\20260512-132906\`. Summary report:

```text
generated\production-analysis\20260512-132906\summary.md
```

That sample contained 25 decoded programs, 11 programs with motion, 9 with `CALL` instructions, and 10 with output writes. Use `docs\TEMPLATE_ROADMAP.md` as the next template-design guide.

Resource candidate report:

```text
generated\production-analysis\20260512-132906\resource-report.md
```

It found 14 distinct `CALL` targets, 25 IO write states, and 25 register references in the decoded sample. Treat these as candidates only; do not add them to `config\cell-map.psd1` without review.

`AI_CELLCHK` is the next generated no-motion template. It was user-approved, uploaded, read back from robot `MD:`, hash verified, decoded successfully, and pendant verified as passed.

## Cell Resource Map

## Controller Inventory

Controller and workstation capabilities now have an explicit inventory model.
The public sample keeps live capabilities disabled:

```powershell
.\tools\Test-FanucControllerInventory.ps1
.\tools\Get-FanucControllerCapability.ps1
```

The local ignored inventory is:

```text
config\controller-inventory.local.psd1
```

Use it for real cell decisions:

```powershell
.\tools\Test-FanucControllerInventory.ps1 -InventoryPath .\config\controller-inventory.local.psd1
.\tools\Get-FanucControllerCapability.ps1 -InventoryPath .\config\controller-inventory.local.psd1
```

See `docs\CONTROLLER_INVENTORY.md`.

`config\cell-map.psd1` is now the reviewed allowlist for generated specs. `tools\Test-FanucProgramSpec.ps1` blocks unapproved register writes, unapproved IO writes, and unapproved generated `CALL` targets before LS generation.

For a new project/workcell, start from `config\cell-map.sample.psd1`. The sample approves no writes. A real policy must declare `PolicyScope`, `ProjectName`, and `WorkcellName`, then explicitly add reviewed register, IO, and CALL resources for that workcell.

Current local commissioning/test policy:

- Scratch register range: `R[90]` through `R[99]`
- Scratch output range: `DO[1]` through `DO[80]`, ON/OFF
- Named current template writes: `R[90]`, `R[91]`, `R[97]`, `R[98]`, `R[99]`, and `DO[1]`

This policy is not universal. Establish a separate cell map and write policy per project/workcell. For this test cell, do not write production/status values outside those scratch ranges without separate approval. `R[103]`, `R[107]`, and `R[110]` are read-only status/sample registers in the current SNPX map. `R[110]` contains a fractional robot value; SNPX readback uses a 1000x scale to preserve values such as `21.209`.

No generated `CALL` targets are approved yet.

## Cell Status Plan

`config\cell-observations.psd1` now defines read-only observation candidates. It generated:

```text
generated\cell-status\latest\status-plan.md
generated\cell-status\latest\status-plan.json
```

Current plan scope: 8 registers, 4 IO signals, 4 program presence checks, and 4 operator checks. This is a read-only planning artifact for future SNPX, PCDK, or KAREL TCP snapshots; it does not grant write permission.

Snapshot tooling now exists:

```powershell
.\tools\New-FanucCellStatusSnapshot.ps1 -Label before-test -Force
.\tools\New-FanucCellStatusSnapshot.ps1 -Label after-test -ValuesPath .\tests\fixtures\valid\cell-status-values.sample.json -Force
.\tools\Compare-FanucCellStatusSnapshot.ps1 -BeforePath <before>\snapshot.json -AfterPath <after>\snapshot.json
```

The latest sample comparison is at `generated\cell-status\latest\sample-comparison.json`.

## SNPX Read-Only Plan

SNPX work is now local to this project. Do not depend on another local checkout for implementation details.

Key files:

```text
config\snpx-readonly.psd1
docs\SNPX_READONLY.md
docs\SNPX_WRITES.md
docs\SNPX_IMPLEMENTATION_NOTES.md
vendor\snpx-codec\
```

The plan uses SNPX V2 on TCP `60008` with private per-connection `$SNPX_ASG` projection into `%R`. Current assignments use system probes plus ASG slots 1 through 12 and `%R00001` through `%R00028` for selected marker registers, production-sample registers, and output states.

Live reads are not enabled yet. The live reader must connect, probe `$SNPX_PARAM.$VERSION` and `$SNPX_PARAM.$NUM_CIMP`, run `CLRASG`, run `SETASG` for every configured row, verify `$SNPX_ASG` by readback, then read `%R`. Unassigned `%R` values can return zero, so verification is mandatory.

SNPX writes are planned separately in `config\snpx-writes.psd1`. This is intentional: status snapshots stay read-only, while command writes get their own allowlist, value validation, pre-read/write/post-read evidence, and human approval gate. The current write plan includes `R[90]`, `R[91]`, `R[97]`, `R[98]`, `R[99]`, and `DO[1]`, all tied back to `config\cell-map.psd1`.

Dynamic SNPX scratch write planning is available for this local commissioning/test policy. `R[95]` and `DO[2]` style targets inside `R[90]`-`R[99]` and `DO[1]`-`DO[80]` use a temporary private ASG projection at `%R00079` for the current connection instead of expanding the read snapshot map. Outputs written `ON` still require restoration to `OFF`.

Use the wrapper for repeatable scratch proofs:

```powershell
.\tools\Invoke-FanucSnpxScratchProof.ps1 -Fanuc "R[95]" -Value 9501
.\tools\Invoke-FanucSnpxScratchProof.ps1 -Fanuc "R[95]" -Value 9501 -Execute -ApprovalPhrase "I approve live SNPX write: R[95]=9501 via %R00079 dynamic ASG"
.\tools\Invoke-FanucSnpxScratchProof.ps1 -Fanuc "DO[2]" -State ON -Execute -ApprovalPhrase "I approve live SNPX write: DO[2]=ON via %R00079 dynamic ASG"
```

Live SNPX writes now require exact approval text from the generated plan. Output writes that request `ON` include a restoration section and require `-RestoreAfterWrite`; evidence records write and restore readbacks separately.

Useful commands:

```powershell
.\tools\Test-FanucSnpxReadonlyConfig.ps1
.\tools\Get-FanucSnpxAddressMap.ps1 -WriteMarkdown
.\tools\Get-FanucSnpxCommissioningMatrix.ps1 -WriteMarkdown
.\tools\Invoke-FanucSnpxReadSnapshot.ps1 -PlanOnly
.\tools\Test-FanucSnpxWriteConfig.ps1
.\tools\New-FanucSnpxWritePlan.ps1 -Fanuc "R[99]" -Value 123
.\tools\Invoke-FanucSnpxCodecTool.ps1 -Operation probe
.\tools\Invoke-FanucSnpxCodecTool.ps1 -Operation read-r -Start 1 -Count 9
.\tools\Invoke-FanucSnpxLiveRead.ps1
```

## Move Notes

The project was moved, so project-local config is now portable. `config\robot.psd1` uses repo-relative `RobotIniPath = "config\robot.ini"`, and the build script requires the `.LS` filename and `/PROG` header to match before compiling.
