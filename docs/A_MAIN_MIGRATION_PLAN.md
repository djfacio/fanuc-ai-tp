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

- Indefinite CNC wait: `DI[104:Sync1]`
- Indefinite tube insertion waits: `DI[105:Sync2]`
- Indefinite gripper close/open proof in `F_UNLOAD_CNC`: `DI[106:G1 Closed]`
- `RUN F_FLEXI_LOADER` lacks a reviewed single-instance/heartbeat/stop contract
- Proposed `A_MAIN` state/status registers need project approval before writes
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

The proposed state model is in `R[80:A_CELL_STATE]` and the proposed step status
is `R[90:A_STEP_STATUS]`. These are not approved yet.

## Next Decisions Required

Before `A_MAIN.LS` should be generated, decide:

- Timeout for CNC `Sync1`, and what alarm/recovery should happen.
- Timeout for tube insertion `Sync2`, and whether unload/load need different
  recovery behavior.
- Timeout for `G1 Closed` proof and what state to preserve if it fails.
- Whether `A_MAIN` can call existing `F_` station routines for the first robot
  test.
- Whether `F_FLEXI_LOADER` remains `F_` during first test or must become
  `A_FLEXI_LOADER` first.
- Which registers are approved for `A_MAIN` state/status.

## Validation

Validate the migration contract:

```powershell
.\tools\Test-FanucWorkflowMigrationSpec.ps1 -SpecPath .\examples\applications\A_MAIN.workflow-migration.json
```

The expected current result is `IsValid=True` and `ReadyForGeneration=False`.
