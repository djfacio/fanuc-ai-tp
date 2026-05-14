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
- `docs\PHASE_1_SUMMARY.md`
- `docs\PHASE_2_PLAN.md`
- `docs\REAL_APPLICATION_WORKFLOW.md`
- `docs\SAFETY.md`
- `docs\STANDARDS_RULES.md`
- `docs\WORKFLOW.md`
- `docs\MOTION_SAFETY.md`
- `docs\INTERFACES.md`
- `docs\COMMUNICATION_STRATEGY.md`
- `docs\PCDK_STRATEGY.md`
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
Use `docs\STANDARDS_RULES.md` as the standards-driven push-back rulebook. When designing or reviewing generated `A_` production programs, challenge missing state models, timeouts, recovery behavior, async-task ownership, resource policy, and evidence instead of optimizing for agreement.

Use `config\template-catalog.psd1` as the reviewed deterministic template list. Run `tools\Test-FanucTemplateCatalog.ps1` after adding or changing example specs/templates.
Use `tools\New-FanucProjectPack.ps1` for real workcell/project folders outside this public toolchain repo. Project packs keep `applications\`, `config\`, `generated\`, `evidence\`, and `notes\` together under the project folder. Use `tools\Invoke-FanucMotionWorkflow.ps1 -ProjectPath <project-pack> -SpecPath .\applications\<spec>.motion-application.json` for pack-local generation.
Use `config\interface-strategy.psd1` and `tools\Test-FanucInterfaceStrategy.ps1` before adding KAREL, PCDK, or new bridge behavior. KAREL TCP must remain disabled until schemas, robot-resident code, deployment, rollback, and tests are reviewed.
Use `config\pcdk-snapshot.psd1`, `docs\PCDK_STRATEGY.md`, and `tools\New-FanucPcdkSnapshot.ps1` for PCDK work. PCDK is allowed only as a read-only evidence/introspection layer by default. Do not use PCDK task control, program selection, FTP upload/delete, IO writes, frame/position updates, or motion-related methods without a separate reviewed policy.
Use `tools\Invoke-FanucProjectHealthCheck.ps1 -WriteMarkdown` for an offline/read-only project preflight. It must not execute live robot reads or controller writes.
Use `schemas\motion-application-spec.schema.json` and `tools\Test-FanucMotionApplicationSpec.ps1` before any real application or motion generation. `ReadyForGeneration=false` is acceptable during planning. The reviewed offline motion generator is `tools\New-FanucMotionLsFromSpec.ps1` with templates `pr-waypoint-sequence-v1`, `approach-process-retract-v1`, and `io-motion-sequence-v1`; it emits only reviewed `UFRAME_NUM`, `UTOOL_NUM`, `PAYLOAD[n]`, reviewed `J/L PR[n]` moves, and allowlisted IO actions for the IO template. Use `tools\Invoke-FanucMotionWorkflow.ps1` for the one-command local motion generation/compile/round-trip/review-packet workflow. Use `tools\New-FanucRoboguideEvidencePacket.ps1` against the generated `motion-application-spec.json` when optional RoboGuide/manual evidence notes are useful.

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
.\tools\New-NoMotionProgram.ps1 -Name A_TEST -Message "A TEST OK" -Register 99 -Value 456
```

To read an existing robot TP program without modifying the robot:

```powershell
.\tools\Read-FanucTpProgram.ps1 -Program F_MAIN -Force
```

This downloads `F_MAIN.TP` from robot `MD:` into `downloaded\tp\` and decodes readable `.LS` into `downloaded\ls\`.

## Safety Rules

- Keep new generated program names prefixed with `A_`. Existing `AI_` programs are legacy generated programs and remain recognized by validation/reporting tools.
- Keep the `.LS` filename and `/PROG` header identical. The build script checks both before compiling.
- Keep generated register writes, IO writes, and CALL targets allowlisted in `config\cell-map.psd1`. The spec validator enforces this map.
- This repo's current scratch write scope is for the local commissioning/test project only: `R[90]`-`R[99]` and `DO[1]`-`DO[80]`. Establish a separate policy per project/workcell. Do not write production/status values outside the active project's policy, including `R[103]`, `R[107]`, `R[110]`, or outputs above `DO[80]` in this test cell, without separate approval.
- Use `config\cell-map.sample.psd1` as the no-write starter for a new project/workcell. A project policy must declare `PolicyScope`, `ProjectName`, and `WorkcellName`.
- Use `config\cell-observations.psd1`, `tools\New-FanucCellStatusPlan.ps1`, `tools\New-FanucCellStatusSnapshot.ps1`, and `tools\Compare-FanucCellStatusSnapshot.ps1` for read-only status planning and pre/post evidence. This map does not grant write permission.
- Use `config\snpx-readonly.psd1` for SNPX status planning and `config\snpx-writes.psd1` for SNPX write planning. SNPX live reads and writes must use private per-connection `$SNPX_ASG` mapping on TCP `60008`, verify the ASG table by readback, and use the local `vendor\snpx-codec\` source rather than another local project path.
- Use `tools\Get-FanucSnpxCommissioningMatrix.ps1` before expanding SNPX mappings. The matrix must show no `%R` projection collisions and must make write/restoration gates visible.
- Live SNPX writes must use an approved `New-FanucSnpxWritePlan.ps1` plan, exact `operatorApproval.requiredPhrase`, and `-AcceptLiveWrite`. Output writes that require restoration must use `-RestoreAfterWrite` so evidence includes post-restore readback.
- Dynamic SNPX scratch writes use one temporary private ASG projection from `config\snpx-writes.psd1` and must still pass the project cell-map policy and live-write approval gates.
- Prefer `tools\Invoke-FanucSnpxScratchProof.ps1` for repeatable scratch write proofs. Run it once in dry mode to get the exact approval phrase, then execute only with `-Execute` and that phrase.
- Use `config\controller-inventory.sample.psd1` as the publishable capability model and `config\controller-inventory.local.psd1` for real local cell/tool details. Validate with `tools\Test-FanucControllerInventory.ps1` and summarize with `tools\Get-FanucControllerCapability.ps1`.
- Run `tools\Test-FanucLsSafety.ps1` before compiling or uploading generated `.LS` files. `Invoke-FanucTpBuild.ps1` also runs this gate automatically.
- Run `tools\Invoke-FanucTpRoundTrip.ps1` before upload. It records PrintTP decode evidence in `generated\jobs\<PROGRAM>\roundtrip.json`.
- Prefer `tools\Invoke-FanucLocalWorkflow.ps1` for local end-to-end evidence generation.
- Run `tools\Update-FanucJobManifest.ps1` to collect local evidence. `localEvidencePassed=true` is not the same as robot upload approval.
- Use `tools\Set-FanucJobStatus.ps1` to record human review and upload status. Use `-WhatIf` for dry runs.
- `Invoke-FanucTpBuild.ps1 -Upload` blocks manifest-backed jobs until `readyForUpload=true`.
- Use `tools\Get-FanucJobSummary.ps1` to review local job status, and `tools\Get-FanucJobSummary.ps1 -IncludeRobot` or `tools\Get-FanucRobotDirectory.ps1` to reconcile against robot `MD:` without running programs.
- Use `tools\Save-FanucRobotInventory.ps1` for read-only robot `MD:` snapshots, `tools\Invoke-FanucProductionProgramAnalysis.ps1` for controlled download/decode analysis of selected existing TP programs, `tools\Get-FanucProductionAnalysisSummary.ps1 -WriteMarkdown` for count summaries, and `tools\Get-FanucProductionResourceReport.ps1 -WriteMarkdown` for CALL/IO/register candidates.
- Include generated-prefix programs (`A_*` and legacy `AI_*`) by default in inventory analysis and dependency cleanup policies. Use `-ExcludeGeneratedPrograms` only when a deliberately non-generated view is requested.
- Use `tools\Remove-FanucTpNonDependencies.ps1` only from a reviewed `New-FanucTpDependencyMap.ps1` report. It refuses missing dependencies and dynamic references, skips `CleanupProtectedPrograms` from `config\robot.psd1`, backs up present candidates to `generated\robot-cleanup\`, and records controller delete refusals per file. `-BCKEDT-` is cleanup-protected and must never be attempted again.
- Macro programs are normal `.TP` programs whose decoded `/PROG` line includes `Macro`, for example `/PROG  F_OPENG1    Macro`; do not treat `.MR` as a proven file extension. Keep notes in `docs\MACRO_PROGRAMS.md`.
- RoboGuide/manual evidence is optional project evidence unless a future project policy explicitly makes it a gate.
- Use `tools\New-FanucRoboguideEvidencePacket.ps1` to generate structured RoboGuide/manual evidence packets from specs. IO-sequence and motion packets require before/after snapshots.
- Do not auto-run uploaded programs.
- Do not overwrite production robot programs.
- Keep early/generated programs no-motion unless the user explicitly asks for motion and provides frames, tools, points, speeds, payload assumptions, and verification plan.
- Operator-owned robot-side verification is outside the tracked code-generation gates.
- Do not generate DCS edits, system variable writes, UOP changes, KAREL, `RUN`, or `ABORT` behavior unless explicitly requested and reviewed.
- Run `tools\Invoke-FanucToolTests.ps1` after changing validators, schemas, or generators.

## Known Quirks

- `MakeTP` may use the selected RoboGuide robot profile and output folder. The project carries `config\robot.ini`, referenced through repo-relative `RobotIniPath`, so fresh sessions can compile without rerunning `setrobot.exe`.
- `PrintTP` expects the `.TP` filename to match the internal program name. Robot readback files are stored under `generated\jobs\<PROGRAM>\upload-readback\<PROGRAM>.TP` for this reason.
- The robot FTP listing lowercases uploaded filenames, but `AI_HELLO.TP` still appears/selects correctly on the pendant.
- The FANUC FTP server may emit an early `500 Command not understood` before login while still completing a directory transfer with `226 ASCII Transfer complete`; treat the completed transfer as usable.
- The old FANUC web redirect issue was resolved by deleting `MD:\index.htm`, restarting the controller, and clearing Edge cache. A local backup exists at the parent folder as `robot_index_backup.htm`.
