# Phase 2 Plan

Phase 2 starts with richer status and interface design while keeping command authority narrow. The first track is a disabled KAREL/TCP bridge contract: message schemas and examples only, no robot-resident deployment yet.

## Goals

- Define a robot-resident status bridge contract before writing KAREL code.
- Keep SNPX as the proven live read/write path for scratch proofing.
- Expand status snapshots toward richer cell state, alarms, active program, selected frames/tools, and controlled operator prompts.
- Prepare RoboGuide evidence flow for future motion templates.
- Establish the real application workflow for motion before any motion generator is implemented.
- Establish PCDK as a read-only controller snapshot and evidence path.

## Track 1: KAREL/TCP Contract

Initial scope:

- Newline-delimited JSON messages.
- Request/response correlation with `requestId`.
- Status snapshot messages are read-only.
- Reviewed write request schemas exist for future discussion but remain disabled in `config\interface-strategy.psd1`.
- No program run, motion, system variable, DCS, UOP/SOP, or production-program authority.

Starter artifacts:

- `schemas\karel-tcp-message.schema.json`
- `examples\karel\status.snapshot.request.json`
- `examples\karel\status.snapshot.response.json`
- `examples\karel\command.reviewed-write.request.json`
- `examples\karel\command.reviewed-write.response.json`

## Track 2: Health And Commissioning

- Use `tools\Invoke-FanucProjectHealthCheck.ps1 -WriteMarkdown` as the pre-work checkpoint.
- Keep health checks offline by default.
- Add live checks only as explicit commands with clear read/write labels.

## Track 3: RoboGuide Evidence

- Promote evidence packets into repeatable RoboGuide run records.
- Keep physical motion decisions operator-owned while tool gates focus on generation, compile, round-trip, upload, and readback evidence.

## Track 4: Real Application Motion Workflow

- Use `docs\REAL_APPLICATION_WORKFLOW.md` for the application lifecycle.
- Use `schemas\motion-application-spec.schema.json` for motion application intake.
- Use `tools\Test-FanucMotionApplicationSpec.ps1` to distinguish valid planning specs from generation-ready specs.
- Keep motion generation disabled until a reviewed motion template exists.

## Track 5: PCDK Read-Only Evidence

- Use `docs\PCDK_STRATEGY.md` for the PCDK role and safety boundary.
- Use `config\pcdk-snapshot.psd1` for the read-only snapshot plan.
- Use `schemas\controller-snapshot.schema.json` for PCDK snapshot artifacts.
- Use `tools\New-FanucPcdkSnapshot.ps1` in offline plan mode by default.
- Require explicit `-ConnectReadOnly` for live controller reads and keep `controllerWritesExecuted=false`.

## Exit Criteria For Phase 2

- KAREL/TCP message schema and examples validate.
- KAREL bridge remains disabled until deployment, rollback, and tests are reviewed.
- Health check is the standard preflight before live work.
- A richer read-only status model exists independently from write policy.
- Motion application specs can be validated, and generation-ready status is blocked until frame/tool/payload/point/safety/evidence gates pass.
- PCDK snapshot config, schema, sample artifact, and offline plan generation validate without robot writes.
