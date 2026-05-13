# Phase 1 Summary

Phase 1 is complete: this project now has a reviewed, evidence-producing workflow for AI-assisted no-motion FANUC TP generation plus live SNPX read/write proof infrastructure.

## Proven

- Spec-driven no-motion TP generation.
- `.LS` safety validation with `AI_` prefix enforcement and `/PROG` name matching.
- WinOLPC MakeTP compile and PrintTP round-trip evidence.
- Manifest-backed human review, upload gating, and robot readback.
- Public GitHub repository with offline CI.
- Read-only robot inventory and controlled production-program analysis.
- Project-scoped cell policy with a no-write sample policy for new workcells.
- SNPX V2 private per-connection ASG reads on TCP `60008`.
- Fractional SNPX readback for `R[110]` using scaled projection.
- Plan-backed SNPX writes for reviewed scratch resources.
- Dynamic scratch proof wrapper for `R[90]`-`R[99]` and `DO[1]`-`DO[80]` in this local commissioning/test policy.

## Intentionally Not Built

- Automatic program start from PC tooling.
- Production program overwrite behavior.
- Motion generation without a separate frame/tool/point/payload and operator-owned run-decision model.
- KAREL deployment or robot-resident bridge code.
- PCDK automation.
- DCS, UOP/SOP, system variable, or controller configuration writes.

## Closeout Checks

Run:

```powershell
.\tools\Invoke-FanucProjectHealthCheck.ps1 -WriteMarkdown
.\tools\Invoke-FanucToolTests.ps1
cargo test --manifest-path .\vendor\snpx-codec\Cargo.toml
```

The health check is offline/read-only with respect to the robot: it validates project config and emits summary artifacts without live controller reads or writes.

## Phase 1 Definition Of Done

- Offline validators pass.
- GitHub CI passes.
- `HANDOFF.md` describes the current robot and project state.
- Any live evidence remains ignored under `generated/`.
- New workcells start from `config\cell-map.sample.psd1`, not from this test cell's scratch policy.
