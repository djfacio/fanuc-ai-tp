# FANUC AI TP Workflow

Clean workspace for generating, compiling, and uploading small FANUC TP programs.

For a fresh Codex session, read [AGENTS.md](AGENTS.md) and [HANDOFF.md](HANDOFF.md) first.

This project targets the R-30iB Mate Plus controller at `192.168.5.10` and uses:

- WinOLPC `MakeTP` to compile `.LS` source into `.TP`
- Robot FTP with `anonymous` / `guest`
- A required `AI_` program-name prefix
- A checked `/PROG` header that must match the `.LS` filename
- Project-owned JSON schema and safety-rule validation
- Reviewed cell resource map validation for register, IO, and future CALL targets
- No auto-run behavior

## Folders

```text
config/              Robot, FTP, and MakeTP settings
config/cell-map.psd1 Reviewed register/IO/CALL allowlist
config/cell-observations.psd1 Read-only status observation plan
config/snpx-readonly.psd1 SNPX V2 read-only ASG projection plan
config/snpx-writes.psd1 SNPX V2 write allowlist and planning gates
config/safety-rules.psd1  Blocked LS source patterns
generated/sources/   AI-generated .LS source files
generated/compiled/  Compiled .TP files
generated/jobs/      Per-program spec/source/evidence folders
logs/                FTP upload logs
tools/               PowerShell workflow scripts
docs/                Strategy, workflow, and safety notes
schemas/             Structured program spec schemas
examples/            Example reviewed program specs
vendor/snpx-codec/   Local Rust SNPX/SRTP codec source for future live reads
```

## Generate From A Spec

Run the full local evidence workflow:

```powershell
.\tools\Invoke-FanucLocalWorkflow.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json -Force
```

This validates the spec, generates `.LS`, runs LS safety, compiles with MakeTP, decodes with PrintTP, records simulation status, refreshes the manifest, and writes `review-packet.md`.

Or run the steps manually.

Validate the example spec:

```powershell
.\tools\Test-FanucJsonSchema.ps1 -JsonPath .\examples\AI_HELLO.program-spec.json -SchemaPath .\schemas\program-spec.schema.json
.\tools\Test-FanucCellMap.ps1
.\tools\Test-FanucProgramSpec.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json
```

Generate `.LS` from it:

```powershell
.\tools\New-FanucLsFromSpec.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json -Force
```

This writes:

```text
generated/sources/AI_HELLO.LS
generated/jobs/AI_HELLO/spec.json
generated/jobs/AI_HELLO/AI_HELLO.LS
```

## Create A Safe No-Motion Program Directly

From this folder:

```powershell
.\tools\New-NoMotionProgram.ps1 -Name AI_HELLO -Message "AI FTP upload OK" -Register 99 -Value 123
```

## Compile Only

Validate first:

```powershell
.\tools\Test-FanucLsSafety.ps1 -LsPath .\generated\sources\AI_HELLO.LS
```

Then compile:

```powershell
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_HELLO.LS -Force
```

## Round-Trip Check

Compile with MakeTP, decode with PrintTP, and compare normalized `/MN` instructions:

```powershell
.\tools\Invoke-FanucTpRoundTrip.ps1 -LsPath .\generated\sources\AI_HELLO.LS -Force
```

This writes:

```text
generated/jobs/AI_HELLO/decoded.LS
generated/jobs/AI_HELLO/roundtrip.json
```

## Job Manifest

Collect the job evidence into a manifest:

```powershell
.\tools\Update-FanucJobManifest.ps1 -ProgramName AI_HELLO
```

This writes:

```text
generated/jobs/AI_HELLO/validation.json
generated/jobs/AI_HELLO/manifest.json
generated/jobs/AI_HELLO/review-packet.md
```

`manifest.json` separates local evidence from deployment readiness. `localEvidencePassed` can be true after spec validation, LS safety, and round-trip checks pass. `readyForUpload` remains false until human review/upload policy is explicitly recorded.

Record human review after manual inspection:

```powershell
.\tools\Set-FanucJobStatus.ps1 -ProgramName AI_HELLO -HumanReviewStatus approved -Reviewer "Your Name" -HumanReviewNotes "Reviewed no-motion register/message program."
```

Preview a status change without writing evidence:

```powershell
.\tools\Set-FanucJobStatus.ps1 -ProgramName AI_HELLO -HumanReviewStatus approved -Reviewer "Your Name" -WhatIf
```

`Invoke-FanucTpBuild.ps1 -Upload` refuses to upload a job with a manifest unless `readyForUpload=true`. Successful uploads are recorded back into the manifest automatically.

Create a review packet:

```powershell
.\tools\Get-FanucReviewPacket.ps1 -ProgramName AI_HELLO
```

Record simulation evidence:

```powershell
.\tools\Set-FanucSimulationEvidence.ps1 -ProgramName AI_HELLO -Status not-required -Notes "No-motion workflow."
```

## Compile And Upload

```powershell
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_HELLO.LS -Force -Upload
```

The robot will receive `AI_HELLO.TP` on `MD:`.

After upload, verify the robot copy by readback:

```powershell
.\tools\Invoke-FanucUploadReadback.ps1 -ProgramName AI_HELLO -Force
```

The readback TP is stored as `generated/jobs/<PROGRAM>/upload-readback/<PROGRAM>.TP` because PrintTP expects the filename to match the internal program name.

List generated AI programs currently present on robot `MD:`:

```powershell
.\tools\Get-FanucRobotDirectory.ps1 -Pattern "AI_*.TP"
```

Summarize local manifests, readback evidence, pendant status, and robot presence:

```powershell
.\tools\Get-FanucJobSummary.ps1 -IncludeRobot
```

If robot FTP is unavailable, the summary still reports local manifest/readback status and marks the robot lookup unavailable.

The controller listing may report uploaded files in lowercase and with size `0`; use the normalized `ProgramName` and readback hash evidence for reconciliation.

Save a timestamped read-only inventory snapshot of robot `MD:`:

```powershell
.\tools\Save-FanucRobotInventory.ps1
.\tools\Get-FanucJobSummary.ps1 -UseLatestRobotInventory
```

Analyze existing non-`AI_` TP programs from the saved inventory without modifying the robot:

```powershell
.\tools\Invoke-FanucProductionProgramAnalysis.ps1 -FromInventory -Limit 3 -Force
.\tools\Get-FanucProductionAnalysisSummary.ps1 -WriteMarkdown
.\tools\Get-FanucProductionResourceReport.ps1 -WriteMarkdown
```

Generate a RoboGuide execution checklist from a manifested job:

```powershell
.\tools\New-FanucRoboguideTestPlan.ps1 -ProgramName AI_CELLCHK -Force
```

Generate a read-only cell status plan:

```powershell
.\tools\Test-FanucCellObservations.ps1
.\tools\New-FanucCellStatusPlan.ps1 -Force
.\tools\New-FanucCellStatusSnapshot.ps1 -Label before-test -Force
```

Validate and emit the SNPX read-only address plan:

```powershell
.\tools\Test-FanucSnpxReadonlyConfig.ps1
.\tools\Get-FanucSnpxAddressMap.ps1 -WriteMarkdown
.\tools\Invoke-FanucSnpxReadSnapshot.ps1 -PlanOnly
```

Validate and emit an SNPX write plan:

```powershell
.\tools\Test-FanucSnpxWriteConfig.ps1
.\tools\New-FanucSnpxWritePlan.ps1 -Fanuc "R[99]" -Value 123
```

Run the local Rust SNPX codec wrapper for commissioning reads:

```powershell
.\tools\Invoke-FanucSnpxCodecTool.ps1 -Operation probe
.\tools\Invoke-FanucSnpxCodecTool.ps1 -Operation read-r -Start 1 -Count 9
.\tools\Invoke-FanucSnpxLiveRead.ps1
```

## Read An Existing Robot TP Program

Download a `.TP` file from robot `MD:` and decode it to readable `.LS`:

```powershell
.\tools\Read-FanucTpProgram.ps1 -Program AI_HELLO -Force
```

Output files go to:

```text
downloaded/tp/
downloaded/ls/
```

## Safety Rules

- Program names must start with `AI_`.
- The `.LS` filename and `/PROG` header must match exactly.
- Register writes, IO writes, and generated CALL targets must be approved in `config\cell-map.psd1`.
- Uploads do not run programs.
- The build blocks obvious risky patterns such as system variable writes, DCS references, UOP references, `RUN`, and `ABORT`.
- Use generated programs in T1/manual verification first.
- Do not use this workflow to overwrite production programs.

## Portable Paths

Project-local config paths are repo-relative. In `config/robot.psd1`, `RobotIniPath = "config\robot.ini"` resolves from this repo root, so the folder can move. Machine-installed tooling, such as WinOLPC and RoboGuide workcell paths, may remain absolute.

## Project Direction

Read `docs/STRATEGY.md`, `docs/SAFETY.md`, and `docs/WORKFLOW.md` before expanding generators. The intended architecture is plan/spec first, deterministic `.LS` generation second, then validation, MakeTP, PrintTP round-trip, RoboGuide testing, upload, and pendant verification.

The first example spec is `examples/AI_HELLO.program-spec.json`.

Planning docs for the next phase:

- `docs/COMMUNICATION_STRATEGY.md`
- `docs/PROGRAM_TEMPLATES.md`
- `docs/TEMPLATE_ROADMAP.md`
- `docs/CELL_RESOURCE_MAP.md`
- `docs/CELL_STATUS_PLAN.md`
- `docs/SNPX_READONLY.md`
- `docs/SNPX_WRITES.md`
- `docs/SNPX_IMPLEMENTATION_NOTES.md`
- `docs/ROBOGUIDE_EVIDENCE_PIPELINE.md`

Additional safe starter specs:

- `examples/AI_REGDIAG.program-spec.json`
- `examples/AI_IODIAG.program-spec.json`
- `examples/AI_PRCHECK.program-spec.json`
- `examples/AI_FRMTOOL.program-spec.json`
- `examples/AI_SNAPSHOT.program-spec.json`
- `examples/AI_CELLCHK.program-spec.json`

## Tests

Run the local validator fixture suite:

```powershell
.\tools\Invoke-FanucToolTests.ps1
```

## Proven Baseline

`AI_HELLO.TP` was compiled with MakeTP and executed cleanly on the robot. It only displays a message and writes `R[99]=123`.
