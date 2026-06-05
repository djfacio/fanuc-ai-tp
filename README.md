# FANUC AI TP Workflow

Tools and workflow notes for planning, generating, validating, and deploying
AI-assisted FANUC TP programs.

For a fresh Codex session, read [AGENTS.md](AGENTS.md) and [HANDOFF.md](HANDOFF.md) first.

## Public Safety Notice

This repository can generate robot programs and includes tooling for FTP upload
and SNPX reads/writes. Treat every live controller command as machine-control
software:

- Run offline validation before compiling or uploading.
- Review generated `.LS` source and evidence manually.
- Treat physical run decisions as operator-owned robot-side decisions.
- Keep robot IPs, credentials, packet captures, downloaded programs, and run
  evidence out of Git.
- Do not use this workflow to overwrite production programs.

The checked-in config is a commissioning starting point, not a universal cell
configuration. Review `config/robot.psd1`, `config/cell-map.psd1`,
`config/snpx-readonly.psd1`, and `config/snpx-writes.psd1` for your own robot
before any live operation.

For this local commissioning/test project only, the scratch write boundary is
`R[90]` through `R[99]` and `DO[1]` through `DO[80]`. Establish a separate
cell map and write policy for each project/workcell.

## Capabilities

This project currently supports:

- WinOLPC `MakeTP` to compile `.LS` source into `.TP`
- A required `A_` program-name prefix for new generated programs. Existing `AI_` programs remain recognized as legacy generated programs.
- A checked `/PROG` header that must match the `.LS` filename
- Project-owned JSON schema and safety-rule validation
- Reviewed cell resource map validation for register, IO, and future CALL targets
- Robot FTP upload/readback evidence when configured locally
- SNPX V2 per-connection ASG read/write planning and live proof tooling
- PCDK read-only controller snapshot planning for richer evidence
- No auto-run behavior

## Tooling Requirements

You can use the offline planning, schema validation, LS generation, cell-map
validation, documentation, project-pack creation, and Rust SNPX codec tests
without RoboGuide, WinOLPC, PCDK, or a robot connection.

WinOLPC is required only for workflows that compile `.LS` to `.TP` with
`MakeTP` or decode `.TP` files with `PrintTP`, including the round-trip evidence
gate and upload-ready local workflow.

RoboGuide is optional evidence tooling. It is useful for simulation/manual
review packets and workcell-specific compile context, but this repo does not
require RoboGuide for offline spec review, LS generation, SNPX planning, Robot
Server comment/alarm planning, or documentation work.

PCDK is optional and read-only by default in this repo. Use it only for the
documented controller snapshot/evidence path unless a project policy explicitly
expands its authority.

Live robot FTP, SNPX, and Robot Server access are optional and require a local
reviewed config plus each tool's approval gates. The public CI/offline tests do
not connect to FANUC software or a controller.

## Controller Feature Requirements

Offline repository work does not prove that a controller has the options needed
for live features. For each robot, record the actual installed/enabled
controller capabilities in a local controller inventory or project notes before
using live tools.

- FTP upload/readback requires the controller FTP server to be enabled and
  reachable with reviewed credentials.
- SNPX live reads/writes require the robot-side SNPX/SRTP capability to be
  installed/enabled and reachable on the configured port. This project uses SNPX
  V2 with private per-connection ASG mapping, typically on TCP `60008`.
- Robot Server comment/alarm tools require the controller's HTTP Robot Server
  pages to be enabled and reachable from the workstation.
- KAREL helper programs require controller support for KAREL program execution
  plus a reviewed compile/deploy path for `.KL`/`.PC` artifacts.
- TCP socket/KAREL bridge features require KAREL plus the controller socket
  messaging capability and a reviewed port/message policy.
- PCDK live snapshots require a licensed/configured PCDK workstation path and
  controller connectivity. PCDK remains read-only by default in this repo.

Controller option names and menus vary by robot software version and installed
packages. Do not infer these capabilities from this public repo; confirm them
on the target controller.

## Quick Start

Run the offline validator suite:

```powershell
.\tools\Invoke-FanucToolTests.ps1
```

After local WinOLPC and `robot.local.psd1` setup is reviewed, include the
compile/round-trip gate:

```powershell
.\tools\Invoke-FanucToolTests.ps1 -IncludeWinOlpc
```

Run the offline/read-only project health check:

```powershell
.\tools\Invoke-FanucProjectHealthCheck.ps1 -WriteMarkdown
```

Run the vendored SNPX codec tests:

```powershell
cargo test --manifest-path .\vendor\snpx-codec\Cargo.toml
```

Generate local evidence for a no-motion example:

```powershell
.\tools\Invoke-FanucLocalWorkflow.ps1 -SpecPath .\examples\AI_HELLO.program-spec.json -Force
```

Live robot operations require local review of `config/robot.psd1` and explicit
human approval gates in the relevant tools.

Create a local robot config instead of guessing installed FANUC paths:

```powershell
.\tools\New-FanucRobotConfig.ps1 -OutputPath .\config\robot.local.psd1 -RobotIp 192.0.2.10
```

Review the generated file and pass it with `-ConfigPath` for live/local work.
See `docs/SETUP_DISCOVERY.md`.

## Folders

```text
config/              Robot, FTP, and MakeTP settings
config/cell-map.psd1 Reviewed register/IO/CALL allowlist
config/cell-map.sample.psd1 Safe starter policy for a new project/workcell
config/cell-observations.psd1 Read-only status observation plan
config/controller-inventory.sample.psd1 Sanitized controller/tool capability inventory
config/snpx-readonly.psd1 SNPX V2 read-only ASG projection plan
config/snpx-writes.psd1 SNPX V2 write allowlist and planning gates
config/pcdk-snapshot.psd1 PCDK read-only snapshot plan
config/template-catalog.psd1 Deterministic TP template catalog
config/interface-strategy.psd1 FTP/SNPX/KAREL/PCDK/RoboGuide interface roles
config/safety-rules.psd1  Blocked LS source patterns
generated/sources/   AI-generated .LS source files
generated/compiled/  Compiled .TP files
generated/jobs/      Per-program spec/source/evidence folders
logs/                FTP upload logs
tools/               PowerShell workflow scripts
docs/                Strategy, workflow, and safety notes
schemas/             Structured program spec schemas
examples/            Example reviewed program specs
vendor/snpx-codec/   Local Rust SNPX/SRTP codec source and test vectors
```

## Controller Inventory

Validate the sanitized public sample:

```powershell
.\tools\Test-FanucControllerInventory.ps1
.\tools\Get-FanucControllerCapability.ps1
```

For a real cell, copy `config/controller-inventory.sample.psd1` to
`config/controller-inventory.local.psd1`, update the local details, then run:

```powershell
.\tools\Test-FanucControllerInventory.ps1 -InventoryPath .\config\controller-inventory.local.psd1
.\tools\Get-FanucControllerCapability.ps1 -InventoryPath .\config\controller-inventory.local.psd1
```

The local inventory file is ignored by Git. See
`docs/CONTROLLER_INVENTORY.md`.

## Project Cell Policy

Each project/workcell needs its own reviewed cell policy. For a new project,
start from:

```text
config/cell-map.sample.psd1
```

Copy it to the project config, set `PolicyScope`, `ProjectName`, and
`WorkcellName`, then add only the register, IO, and CALL resources reviewed for
that workcell. The local commissioning/test policy in this repo does not carry
over automatically.

## Project Packs

Keep real TP generation projects outside this public toolchain repo. Create a
local project pack:

```powershell
.\tools\New-FanucProjectPack.ps1 -Path "C:\FanucProjects\TestProject" -ProjectName TestProject
```

Run motion workflows against the pack:

```powershell
.\tools\Invoke-FanucMotionWorkflow.ps1 `
  -ProjectPath "C:\FanucProjects\TestProject" `
  -SpecPath .\applications\A_TEST_APR.motion-application.json `
  -Force
```

The project pack owns application specs, project-local config, generated
outputs, evidence, and notes. The toolchain repo owns schemas, validators,
generators, and shared docs.

## Template Catalog

Validate and emit the deterministic template catalog:

```powershell
.\tools\Test-FanucTemplateCatalog.ps1
.\tools\Get-FanucTemplateCatalog.ps1 -WriteMarkdown
```

See `docs/TEMPLATE_CATALOG.md`.

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
.\tools\New-NoMotionProgram.ps1 -Name A_HELLO -Message "A FTP upload OK" -Register 99 -Value 123
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
.\tools\Get-FanucRobotDirectory.ps1
```

Summarize local manifests, readback evidence, upload status, and robot presence:

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

Analyze existing TP programs from the saved inventory without modifying the robot. Generated-prefix programs (`A_*` and legacy `AI_*`) are included by default; add `-ExcludeGeneratedPrograms` only when you intentionally want a non-generated view:

```powershell
.\tools\Invoke-FanucProductionProgramAnalysis.ps1 -FromInventory -Limit 3 -Force
.\tools\Get-FanucProductionAnalysisSummary.ps1 -WriteMarkdown
.\tools\Get-FanucProductionResourceReport.ps1 -WriteMarkdown
```

Generate a RoboGuide execution plan from a manifested job:

```powershell
.\tools\New-FanucRoboguideTestPlan.ps1 -ProgramName AI_CELLCHK -Force
```

Generate a RoboGuide/manual evidence packet from a spec:

```powershell
.\tools\Test-FanucRoboguideEvidenceConfig.ps1
.\tools\New-FanucRoboguideEvidencePacket.ps1 -SpecPath .\examples\AI_IODIAG.program-spec.json -WriteMarkdown -Force
```

Build a read-only dependency map for a production main program:

```powershell
.\tools\New-FanucTpDependencyMap.ps1 -RootProgram F_MAIN -Force
```

This downloads/decodes the root program and direct `CALL`/`RUN` closure, lists missing
or non-TP dependencies, and reports TP programs present on robot `MD:` that are
not reachable from the root by static direct `CALL`/`RUN` analysis. Generated-prefix programs (`A_*` and legacy `AI_*`) are included in the report and backup/delete candidates by default.
KAREL `.PC` files are included as present, non-traversed dependencies. Macro TP
programs are identified from the decoded `/PROG ... Macro` marker; see
`docs/MACRO_PROGRAMS.md`.

To back up and delete the non-dependency TP candidates from a reviewed dependency
map:

```powershell
.\tools\Remove-FanucTpNonDependencies.ps1 -DependencyMapPath .\generated\dependency-map\<run>\dependency-map.json
.\tools\Remove-FanucTpNonDependencies.ps1 -DependencyMapPath .\generated\dependency-map\<run>\dependency-map.json -Execute
```

The cleanup tool refuses maps with missing dependencies or dynamic references,
skips candidates already gone from the robot, skips configured
`CleanupProtectedPrograms`, backs up every present candidate to
`generated\robot-cleanup\`, and records controller delete refusals per file.

Validate a real application workflow spec before any motion generation:

```powershell
.\tools\Test-FanucMotionApplicationSpec.ps1 -SpecPath .\examples\applications\AI_APP_PICK_PLACE.motion-application.json
```

Generate offline LS from the first reviewed PR-waypoint motion template:

```powershell
.\tools\New-FanucMotionLsFromSpec.ps1 -SpecPath .\tests\fixtures\valid\AI_MOTION_PR_READY.motion-application.json -Force
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_MOTION_PR_READY.LS -Force
.\tools\Test-FanucMotionGeneratedLs.ps1 -SpecPath .\generated\jobs\AI_MOTION_PR_READY\motion-application-spec.json -LsPath .\generated\sources\AI_MOTION_PR_READY.LS
.\tools\New-FanucRoboguideEvidencePacket.ps1 -SpecPath .\generated\jobs\AI_MOTION_PR_READY\motion-application-spec.json -WriteMarkdown -Force
```

Or run the local motion workflow command:

```powershell
.\tools\Invoke-FanucMotionWorkflow.ps1 -SpecPath .\examples\applications\AI_PR300_PATH.motion-application.json -Force
```

The workflow state names are `planned`, `generationReady`, `generated`, `compiled`, `roundTripPassed`, `reviewed`, `uploaded`, and `readbackPassed`. Operator-owned robot setup and physical run decisions are intentionally not separate tool gates.

The reviewed motion template IDs are:

- `pr-waypoint-sequence-v1`
- `approach-process-retract-v1`
- `io-motion-sequence-v1`

The generator emits reviewed `UFRAME_NUM`, `UTOOL_NUM`, `PAYLOAD[n]`, reviewed `J/L PR[n]` moves, and allowlisted IO actions only for the IO motion template. It does not run programs, write PRs, write frames/tools, or create Cartesian `/POS` records.

Validate and emit the interface strategy before adding KAREL/PCDK bridge work:

```powershell
.\tools\Test-FanucInterfaceStrategy.ps1
.\tools\Get-FanucInterfaceStrategy.ps1 -WriteMarkdown
```

Validate and emit the PCDK read-only snapshot plan:

```powershell
.\tools\Test-FanucPcdkSnapshotConfig.ps1
.\tools\New-FanucPcdkSnapshot.ps1
.\tools\Test-FanucJsonSchema.ps1 -JsonPath .\examples\pcdk\controller-snapshot.plan.json -SchemaPath .\schemas\controller-snapshot.schema.json
```

Use `-SkipComProbe` when running on a machine without PCDK or COM support, such as public CI.

Live PCDK reads require an explicit switch and remain read-only:

```powershell
.\tools\New-FanucPcdkSnapshot.ps1 -HostName 192.168.0.10 -ConnectReadOnly
```

Generate the offline/read-only project health summary:

```powershell
.\tools\Invoke-FanucProjectHealthCheck.ps1 -WriteMarkdown
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
.\tools\Get-FanucSnpxCommissioningMatrix.ps1 -WriteMarkdown
.\tools\Invoke-FanucSnpxReadSnapshot.ps1 -PlanOnly
```

Validate and emit an SNPX write plan:

```powershell
.\tools\Test-FanucSnpxWriteConfig.ps1
.\tools\New-FanucSnpxWritePlan.ps1 -Fanuc "R[99]" -Value 123
```

Create a dry-run scratch proof bundle for this local commissioning/test policy:

```powershell
.\tools\Invoke-FanucSnpxScratchProof.ps1 -Fanuc "R[95]" -Value 9501
.\tools\Invoke-FanucSnpxScratchProof.ps1 -Fanuc "DO[2]" -State ON
```

Dry-run a live SNPX write plan before any robot write:

```powershell
.\tools\Invoke-FanucSnpxLiveWrite.ps1 -PlanPath .\generated\cell-status\snpx-write-plan.json
```

Live write execution requires an approved plan, exact approval phrase, and `-AcceptLiveWrite`. Output writes that require restoration also require `-RestoreAfterWrite`.

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

- New program names must start with `A_`. Legacy `AI_` program names are still accepted for existing examples, tests, and uploaded historical jobs.
- The `.LS` filename and `/PROG` header must match exactly.
- Register writes, IO writes, and generated CALL targets must be approved in `config\cell-map.psd1`.
- Uploads do not run programs.
- The build blocks obvious risky patterns such as system variable writes, DCS references, UOP references, `RUN`, and `ABORT`.
- Operator-owned robot setup and physical path decisions are outside the tracked code-generation gates.
- Do not use this workflow to overwrite production programs.

## Portable Paths

Project-local config paths are repo-relative. In `config/robot.psd1`, `RobotIniPath = "config\robot.ini"` resolves from this repo root, so the folder can move. Machine-installed tooling, such as WinOLPC and RoboGuide workcell paths, may remain absolute.

## Project Direction

Read `docs/STRATEGY.md`, `docs/SAFETY.md`, and `docs/WORKFLOW.md` before expanding generators. The intended architecture is plan/spec first, deterministic `.LS` generation second, then validation, MakeTP, PrintTP round-trip, optional RoboGuide/manual evidence, upload, and readback.

The first example spec is `examples/AI_HELLO.program-spec.json`.

Planning docs for the next phase:

- `docs/PHASE_1_SUMMARY.md`
- `docs/PHASE_2_PLAN.md`
- `docs/REAL_APPLICATION_WORKFLOW.md`
- `docs/COMMUNICATION_STRATEGY.md`
- `docs/KAREL_TCP_BRIDGE.md`
- `docs/PCDK_STRATEGY.md`
- `docs/SOURCE_AUTHORITY.md`
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
- `examples/applications/AI_APP_PICK_PLACE.motion-application.json`
- `examples/applications/AI_PR300_PATH.motion-application.json`
- `examples/pcdk/controller-snapshot.plan.json`

## Tests

Run the local validator fixture suite:

```powershell
.\tools\Invoke-FanucToolTests.ps1
```

Run the Rust SNPX codec suite:

```powershell
cargo test --manifest-path .\vendor\snpx-codec\Cargo.toml
```

GitHub Actions runs both offline suites on `main` pushes and pull requests.

## Proven Baseline

`AI_HELLO.TP` was compiled with MakeTP and executed cleanly on the robot. It only displays a message and writes `R[99]=123`.
