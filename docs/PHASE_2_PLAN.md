# Phase 2 Plan

Phase 2 starts with richer status and interface design while keeping command authority narrow. The first track is a disabled KAREL/TCP bridge contract: message schemas and examples only, no robot-resident deployment yet.

## Goals

- Define a robot-resident status bridge contract before writing KAREL code.
- Keep SNPX as the proven live read/write path for scratch proofing.
- Expand status snapshots toward richer cell state, alarms, active program, selected frames/tools, and controlled operator prompts.
- Prepare RoboGuide evidence flow for future motion templates.

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

- Promote evidence packets from checklists to repeatable RoboGuide run records.
- Keep physical motion disabled until virtual evidence and T1/manual criteria are defined.

## Exit Criteria For Phase 2

- KAREL/TCP message schema and examples validate.
- KAREL bridge remains disabled until deployment, rollback, and tests are reviewed.
- Health check is the standard preflight before live work.
- A richer read-only status model exists independently from write policy.
