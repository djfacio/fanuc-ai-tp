# Cell Status Plan

The cell status plan is the read-only counterpart to `config\cell-map.psd1`.

- `config\cell-map.psd1` controls what generated programs are allowed to write or call.
- `config\cell-observations.psd1` lists what we want to read or manually observe.

The observation map does not grant write permission. It is a planning artifact for future SNPX, PCDK, or KAREL TCP read-only snapshots.

## Commands

Validate the observation map:

```powershell
.\tools\Test-FanucCellObservations.ps1
```

Generate the current read-only checklist:

```powershell
.\tools\New-FanucCellStatusPlan.ps1 -Force
```

Create a blank/manual snapshot from the plan:

```powershell
.\tools\New-FanucCellStatusSnapshot.ps1 -Label before-test -Force
```

Create a snapshot from a values JSON file:

```powershell
.\tools\New-FanucCellStatusSnapshot.ps1 -Label after-test -ValuesPath .\tests\fixtures\valid\cell-status-values.sample.json -Force
```

Compare two snapshots:

```powershell
.\tools\Compare-FanucCellStatusSnapshot.ps1 -BeforePath <before>\snapshot.json -AfterPath <after>\snapshot.json -OutputPath .\generated\cell-status\latest\comparison.json
```

Current output:

```text
generated\cell-status\latest\status-plan.md
generated\cell-status\latest\status-plan.json
generated\cell-status\snapshots\<timestamp>\snapshot.md
generated\cell-status\snapshots\<timestamp>\snapshot.json
```

## Current Scope

The initial plan includes:

- AI marker registers used by reviewed generated programs.
- A few production-analysis register candidates.
- Reviewed or observed DO signals.
- Selected generated and production program presence checks.
- Operator checks for mode, override, frames, and recovery state.

## Next Implementation Choice

Pick one transport for live read-only snapshots:

- SNPX for direct register and IO reads.
- PCDK for richer Windows-side controller access.
- KAREL TCP for a project-owned robot-side status service.

No write behavior should be added from the observation map.

Snapshot values can come from manual entry today and from SNPX, PCDK, or KAREL TCP later. Keep the snapshot shape stable so pre/post verification evidence is transport-independent.
