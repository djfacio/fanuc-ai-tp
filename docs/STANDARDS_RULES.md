# Standards-Driven Generation Rules

This is the living rulebook for AI-assisted FANUC TP generation. It exists to
push project decisions toward accepted industrial practice while leaving final
cell-specific decisions to the responsible robot programmer/integrator.

These rules are informed by ISO 10218-1, ISO 10218-2, ISO 12100, ISO 13849-1,
ANSI/RIA/A3 robot safety practice, and normal production robot integration
conventions. They are not a substitute for a project risk assessment, validated
safety design, or the robot/controller manuals.

## Review Posture

- Challenge assumptions that are only true because one person knows the cell.
- Separate "works on this machine" from "defensible for future maintenance".
- Prefer explicit contracts over tribal knowledge.
- Prefer boring, bounded, observable code over compact clever code.
- Treat TP code as production sequencing, not a safety-rated control system.
- Do not weaken a rule silently. Record the exception, owner, reason, and scope.

## Non-Negotiable Boundaries

- Generated `A_` code must never overwrite or mutate the proven `F_` baseline.
- Generated code must not edit DCS, safety I/O, mastering, frames, tools,
  payloads, system variables, UOP, or controller configuration.
- Generated code must not run programs from PC tooling.
- Generated code must not assume robot-side safety. Safety functions belong in
  validated safety-rated hardware/control systems.
- Every project needs its own resource policy. Scratch permissions from one cell
  do not transfer to another cell.

## Program Architecture

- `A_MAIN` is an orchestrator, not a motion bucket.
- Station motion belongs in small `A_` routines with one clear responsibility.
- Calculation routines, motion routines, peripheral routines, and async tasks
  must be separated unless the exception is justified.
- Existing `F_` routines may be called during migration only when listed in the
  project contract and reviewed as a dependency.
- Every generated program must declare:
  - purpose
  - inputs
  - preconditions
  - touched frames, tools, payloads, PRs, registers, flags, I/O, and calls
  - success criteria
  - failure behavior
  - recovery/restart assumptions

## State And Recovery

- A real application must have an explicit WIP/state model.
- Flags may mirror state, but they must not be the only undocumented state model.
- Every state transition must define what proves the transition succeeded.
- Failure handling must preserve enough WIP state for a human to recover safely.
- Restart behavior must be specified for power-up, abort, fault reset, and manual
  intervention.
- `F_INIT`-style startup code must document which state is reset, which state is
  preserved, and why.

## Waits And Handshakes

- External-device waits must be bounded unless a reviewed exception says why an
  indefinite wait is acceptable.
- A bounded wait must define timeout duration, alarm/status code, outputs to set
  or reset, and WIP state behavior.
- Handshakes must be paired: request, ready/complete, acknowledgement, timeout,
  and reset/clear behavior should be visible.
- One-shot pulses are allowed only when the receiving device's edge/level
  expectation is documented.
- Time waits used for mechanical settling must be named by purpose in the spec.

## Motion Rules

- Every motion routine must set or inherit reviewed `UFRAME_NUM`, `UTOOL_NUM`,
  and payload schedule intentionally.
- Approach, process, and retract points must be explicit.
- Shared safe points must be named and justified by station context.
- FINE/CNT termination must be chosen deliberately, not copied mechanically.
- Speeds must have policy: approach, process, retract, and recovery speed.
- Generated motion should reference reviewed PRs first. Direct Cartesian
  generation requires a stricter reviewed policy.
- Vacuum/grip actions must have a proof of success where available. If no sensor
  exists, that absence must be explicit.

## Async Tasks

- `RUN` is blocked by default for generated code until an async-task contract is
  reviewed.
- Async tasks must have single-instance protection, heartbeat/status, ownership
  of shared flags/registers, and a defined stop/fault behavior.
- A main program must not blindly start a task that might already be running.
- Background logic, macro starts, PNS/RSR/UOP starts, and HMI/PLC starts must be
  included in dependency and recovery discussions.

## Naming And Resource Conventions

- Generated programs use `A_`.
- Existing `AI_` programs are legacy generated artifacts only.
- Production baseline programs such as `F_` are read/reference dependencies
  unless explicitly migrated.
- Registers, PRs, flags, I/O, and calls must come from the project cell map or a
  reviewed project-specific policy.
- Program comments should be short on the pendant; richer contracts belong in
  specs and review packets.

## Evidence Required Before Upload

- Spec validation passed.
- LS safety validation passed.
- MakeTP compile passed.
- PrintTP round trip passed.
- Review packet generated.
- Dependency map reviewed for calls, runs, macros, KAREL `.PC`, and protected
  programs.
- Human review recorded.
- Upload/readback evidence recorded after upload.

## Discussion Rules

- Codex should push back when the proposed design lacks state, timeout,
  recovery, ownership, or evidence.
- The human owner may override a recommendation, but the override must be
  recorded as project policy.
- "I know this cell" is valid input, but the generated project must capture what
  matters so another competent person can maintain it later.
