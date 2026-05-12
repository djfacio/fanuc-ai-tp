# Codex Project Notes

This is a FANUC R-30iB Mate Plus TP generation/upload workspace.

## Current Robot

- Controller: FANUC R-30iB Mate Plus
- Robot IP: `192.168.5.10`
- PC robot-network IP seen earlier: `192.168.5.200`
- FTP login: `anonymous` / `guest`
- FTP target device: robot `MD:`
- Controller FTP server has been configured and tested.

## Proven Workflow

The controller does not have FANUC ASCII Upload installed, so do not expect `.LS` files to load directly on the robot.

The working path is:

```text
.LS source -> WinOLPC MakeTP -> .TP binary -> FTP upload -> select/run on pendant
```

`AI_HELLO.LS` was compiled into `AI_HELLO.TP`, uploaded by FTP, selected on the pendant, and executed cleanly. It only displayed a message and wrote `R[99]=123`.

## Local Tooling

- MakeTP path: `C:\Program Files (x86)\FANUC\WinOLPC\bin\maketp.exe`
- WinOLPC version: `V9.40-1`
- RoboGuide workcell robot path: `C:\Users\Cubic\Documents\My Workcells\TA_Aerospace\Robot_1`
- Project robot config: `config\robot.psd1`
- MakeTP robot ini: `config\robot.ini`
- Project-local paths in `config\robot.psd1` should be repo-relative, such as `config\robot.ini`, so the folder can move without breaking MakeTP/PrintTP. Keep machine-installed tools and RoboGuide workcell paths absolute unless they are moved too.

## Project Direction

This repo is an AI-assisted FANUC TP workflow, not just a MakeTP/FTP script folder. Read these before adding new generators or deployment behavior:

- `docs\STRATEGY.md`
- `docs\SAFETY.md`
- `docs\WORKFLOW.md`
- `docs\MOTION_SAFETY.md`
- `docs\INTERFACES.md`
- `docs\COMMUNICATION_STRATEGY.md`
- `docs\KAREL_TCP_BRIDGE.md`
- `docs\PROGRAM_TEMPLATES.md`
- `docs\TEMPLATE_CATALOG.md`
- `docs\TEMPLATE_ROADMAP.md`
- `docs\CELL_RESOURCE_MAP.md`
- `docs\CELL_STATUS_PLAN.md`
- `docs\SNPX_READONLY.md`
- `docs\SNPX_WRITES.md`
- `docs\SNPX_IMPLEMENTATION_NOTES.md`
- `docs\CONTROLLER_INVENTORY.md`
- `docs\ROBOGUIDE_TESTING.md`
- `docs\ROBOGUIDE_EVIDENCE_PIPELINE.md`
- `schemas\program-spec.schema.json`
- `examples\AI_HELLO.program-spec.json`

Prefer structured specs and deterministic emitters. Use AI for planning, drafting, inspection, and review support; keep robot-facing artifacts validated, compiled, round-tripped, and manually reviewed.

Use `config\template-catalog.psd1` as the reviewed deterministic template list. Run `tools\Test-FanucTemplateCatalog.ps1` after adding or changing example specs/templates.
Use `config\interface-strategy.psd1` and `tools\Test-FanucInterfaceStrategy.ps1` before adding KAREL, PCDK, or new bridge behavior. KAREL TCP must remain disabled until schemas, robot-resident code, deployment, rollback, and tests are reviewed.

Run commands from this folder:

```powershell
.\tools\Invoke-FanucLocalWorkflow.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json -Force
```

Manual equivalent:

```powershell
.\tools\Test-FanucProgramSpec.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json
.\tools\New-FanucLsFromSpec.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json -Force
.\tools\Test-FanucLsSafety.ps1 -LsPath .\generated\sources\AI_HELLO.LS
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_HELLO.LS -Force
.\tools\Invoke-FanucTpRoundTrip.ps1 -LsPath .\generated\sources\AI_HELLO.LS -Force
.\tools\Set-FanucSimulationEvidence.ps1 -ProgramName AI_HELLO -Status not-required -Notes "No-motion workflow."
.\tools\Update-FanucJobManifest.ps1 -ProgramName AI_HELLO
.\tools\Get-FanucReviewPacket.ps1 -ProgramName AI_HELLO
.\tools\Set-FanucJobStatus.ps1 -ProgramName AI_HELLO -HumanReviewStatus approved -Reviewer "Your Name" -HumanReviewNotes "Reviewed generated LS and evidence."
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_HELLO.LS -Force -Upload
```

The older direct no-motion helper remains useful for quick checks:

```powershell
.\tools\New-NoMotionProgram.ps1 -Name AI_TEST -Message "AI TEST OK" -Register 99 -Value 456
```

To read an existing robot TP program without modifying the robot:

```powershell
.\tools\Read-FanucTpProgram.ps1 -Program F_MAIN -Force
```

This downloads `F_MAIN.TP` from robot `MD:` into `downloaded\tp\` and decodes readable `.LS` into `downloaded\ls\`.

## Safety Rules

- Keep generated program names prefixed with `AI_`.
- Keep the `.LS` filename and `/PROG` header identical. The build script checks both before compiling.
- Keep generated register writes, IO writes, and CALL targets allowlisted in `config\cell-map.psd1`. The spec validator enforces this map.
- This repo's current scratch write scope is for the local commissioning/test project only: `R[90]`-`R[99]` and `DO[1]`-`DO[80]`. Establish a separate policy per project/workcell. Do not write production/status values outside the active project's policy, including `R[103]`, `R[107]`, `R[110]`, or outputs above `DO[80]` in this test cell, without separate approval.
- Use `config\cell-observations.psd1`, `tools\New-FanucCellStatusPlan.ps1`, `tools\New-FanucCellStatusSnapshot.ps1`, and `tools\Compare-FanucCellStatusSnapshot.ps1` for read-only status planning and pre/post evidence. This map does not grant write permission.
- Use `config\snpx-readonly.psd1` for SNPX status planning and `config\snpx-writes.psd1` for SNPX write planning. SNPX live reads and writes must use private per-connection `$SNPX_ASG` mapping on TCP `60008`, verify the ASG table by readback, and use the local `vendor\snpx-codec\` source rather than another local project path.
- Use `tools\Get-FanucSnpxCommissioningMatrix.ps1` before expanding SNPX mappings. The matrix must show no `%R` projection collisions and must make write/restoration gates visible.
- Live SNPX writes must use an approved `New-FanucSnpxWritePlan.ps1` plan, exact `operatorApproval.requiredPhrase`, and `-AcceptLiveWrite`. Output writes that require restoration must use `-RestoreAfterWrite` so evidence includes post-restore readback.
- Use `config\controller-inventory.sample.psd1` as the publishable capability model and `config\controller-inventory.local.psd1` for real local cell/tool details. Validate with `tools\Test-FanucControllerInventory.ps1` and summarize with `tools\Get-FanucControllerCapability.ps1`.
- Run `tools\Test-FanucLsSafety.ps1` before compiling or uploading generated `.LS` files. `Invoke-FanucTpBuild.ps1` also runs this gate automatically.
- Run `tools\Invoke-FanucTpRoundTrip.ps1` before upload. It records PrintTP decode evidence in `generated\jobs\<PROGRAM>\roundtrip.json`.
- Prefer `tools\Invoke-FanucLocalWorkflow.ps1` for local end-to-end evidence generation.
- Run `tools\Update-FanucJobManifest.ps1` to collect local evidence. `localEvidencePassed=true` is not the same as robot upload approval.
- Use `tools\Set-FanucJobStatus.ps1` to record human review, upload, and pendant verification status. Use `-WhatIf` for dry runs.
- `Invoke-FanucTpBuild.ps1 -Upload` blocks manifest-backed jobs until `readyForUpload=true`.
- Use `tools\Get-FanucJobSummary.ps1` to review local job status, and `tools\Get-FanucJobSummary.ps1 -IncludeRobot` or `tools\Get-FanucRobotDirectory.ps1 -Pattern "AI_*.TP"` to reconcile against robot `MD:` without running programs.
- Use `tools\Save-FanucRobotInventory.ps1` for read-only robot `MD:` snapshots, `tools\Invoke-FanucProductionProgramAnalysis.ps1` for controlled download/decode analysis of selected existing TP programs, `tools\Get-FanucProductionAnalysisSummary.ps1 -WriteMarkdown` for count summaries, and `tools\Get-FanucProductionResourceReport.ps1 -WriteMarkdown` for CALL/IO/register candidates.
- If a spec requires RoboGuide, `localEvidencePassed` stays false until simulation evidence is recorded as passed.
- Use `tools\New-FanucRoboguideEvidencePacket.ps1` to generate structured RoboGuide/manual evidence packets from specs. IO-sequence and motion packets require before/after snapshots.
- Do not auto-run uploaded programs.
- Do not overwrite production robot programs.
- Keep early/generated programs no-motion unless the user explicitly asks for motion and provides frames, tools, points, speeds, payload assumptions, and verification plan.
- Use T1/manual verification first.
- Do not generate DCS edits, system variable writes, UOP changes, KAREL, `RUN`, or `ABORT` behavior unless explicitly requested and reviewed.
- Run `tools\Invoke-FanucToolTests.ps1` after changing validators, schemas, or generators.

## Known Quirks

- `MakeTP` may use the selected RoboGuide robot profile and output folder. The project carries `config\robot.ini`, referenced through repo-relative `RobotIniPath`, so fresh sessions can compile without rerunning `setrobot.exe`.
- `PrintTP` expects the `.TP` filename to match the internal program name. Robot readback files are stored under `generated\jobs\<PROGRAM>\upload-readback\<PROGRAM>.TP` for this reason.
- The robot FTP listing lowercases uploaded filenames, but `AI_HELLO.TP` still appears/selects correctly on the pendant.
- The FANUC FTP server may emit an early `500 Command not understood` before login while still completing a directory transfer with `226 ASCII Transfer complete`; treat the completed transfer as usable.
- The old FANUC web redirect issue was resolved by deleting `MD:\index.htm`, restarting the controller, and clearing Edge cache. A local backup exists at the parent folder as `robot_index_backup.htm`.
