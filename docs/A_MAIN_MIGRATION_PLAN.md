# A_MAIN Migration Plan

This plan starts the defensive migration from the proven `F_MAIN` workflow to a
parallel `A_MAIN` workflow. `F_MAIN` remains the production baseline and must not
be overwritten.

## Current Boundary

- Baseline entry: `F_MAIN`
- Generated entry target: `A_MAIN`
- Current artifact: `examples/applications/A_MAIN.workflow-migration.json`
- Current phase: `planning`
- Generation status: not ready

`A_MAIN` is not ready for LS generation yet. That is intentional. The first
contract captures the current process and identifies the assumptions that must be
made explicit before generated robot code is defensible.

## Baseline Shape

`F_MAIN` is a compact orchestrator. It delegates motion and process details to
station routines:

- initialization: `F_INIT`, `F_CALC_POS`
- feeder/vision async behavior: `F_FLEXI_LOADER`
- pick and regrip: `F_CALC_PICK`, `F_PICK`, `F_CALC_REGRIP`, `F_REGRIP`
- CNC exchange: `F_CALC_CNC`, `F_ENTER_CNC`, `F_UNLOAD_CNC`, `F_LOAD_CNC`, `F_EXIT_CNC`
- tube insertion: `F_UNLOAD_TI`, `F_LOAD_TI`
- conveyor/drop: `F_CONV_DROP`, `F_PLACE_CONVEYOR`, `F_CONVEYOR`

The current direct dependency closure is clean: no missing dependencies and no
dynamic `CALL`/`RUN` references in the latest dependency map.

## Standards-Driven Gaps

The blocking gaps are:

- Legacy internal waits, such as the gripper proof wait in `F_UNLOAD_CNC`, are not controlled by an `A_MAIN` wrapper.
- `RUN F_FLEXI_LOADER` lacks a reviewed single-instance/heartbeat/stop contract
- Legacy `F_` calls during migration need an explicit allowlist

## Proposed First A_MAIN Contract

The initial `A_MAIN` should be wrapper-first:

1. Preserve the `F_MAIN` process order.
2. Add explicit state and step status.
3. Keep calls to reviewed `F_` station routines only as a temporary migration
   bridge.
4. Replace unbounded waits with reviewed timeout wrappers.
5. Block or wrap `RUN` until async ownership is approved.
6. Preserve WIP state on failure.

The approved state/status resources are:

- `R[80:A_CELL_STATE]` for lifecycle mode
- `R[90:A_STEP_STATUS]` for step/result status

`R[80]` is not the part-location truth. This is a pipelined cell, so location
truth remains in the existing WIP flags:

- `F[61:PART_4_CNC]`
- `F[62:PART_IN_CNC]`
- `F[63:PART_4_INS]`
- `F[64:PART_IN_INS]`
- `F[65:PART_2_PRINT]`

The lifecycle states are:

- `0 EMPTY_IDLE`: cold start or completed state with all WIP flags OFF
- `10 FILLING`: infeed enabled and the pipeline is being populated
- `20 RUNNING_PIPELINE`: normal production; the system may be partially or fully populated
- `30 DRAINING`: infeed OFF, but loaded/staged WIP is still being processed
- `40 FINISHED`: infeed OFF and all WIP flags OFF
- `900 FAULTED`: explicit failure path with WIP preserved

Fully populated is a derived WIP condition, not a separate lifecycle state. That
keeps the program readable without duplicating state in two places.

The global external wait policy is 180 seconds. On this controller, `$WAITTMOUT`
stores that value as `18000` in hundredths of a second; see
`docs\SYSTEM_VARIABLES.md`. Generated LS must explicitly write
`$WAITTMOUT=18000` immediately before each bounded wait so the value is visible
and easy to tune after observation.

## Next Decisions Required

Before `A_MAIN.LS` should be generated, decide:

- Whether station routines with internal waits, such as `F_UNLOAD_CNC`, must be
  converted to `A_` before the first `A_MAIN` test or can run under a scoped
  exception.
- How `A_MAIN` should prove `F_FLEXI_LOADER`/`A_FLEXI_LOADER` is not already
  running before starting it.
- Decide whether generated code should restore the previous `$WAITTMOUT` value
  after each bounded wait, or whether the project owns it as a fixed cell-level
  180-second setting.

## Validation

Validate the migration contract:

```powershell
.\tools\Test-FanucWorkflowMigrationSpec.ps1 -SpecPath .\examples\applications\A_MAIN.workflow-migration.json
```

The expected current result is `IsValid=True` and `ReadyForGeneration=False`.

Generate the short human review packet:

```powershell
.\tools\Get-FanucWorkflowMigrationReviewPacket.ps1 -SpecPath .\examples\applications\A_MAIN.workflow-migration.json -WriteMarkdown -Force
```

The review packet is the artifact the robot programmer should normally read.
The JSON contract, schema, validator, and dependency maps are audit/tooling
artifacts unless a deeper technical review is needed.
