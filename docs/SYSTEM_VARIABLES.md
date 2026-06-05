# System Variables

This document records FANUC system variables that have project-local evidence.
It is not a general system-variable list. Add entries only after local manual
support, controller readback, or both.

## Source Policy

- Prefer `C:\Dev\Fanuc Robot Manuals` and direct controller evidence.
- Internet references can be used for discovery, not as authority for generated
  robot code.
- Generated programs must not write system variables unless the variable, value,
  unit, scope, and recovery behavior are explicitly reviewed for the active
  project.

## Confirmed Variables

| Variable | Meaning in this project | Evidence | Generator policy |
| --- | --- | --- | --- |
| `$WAITTMOUT` | Conditional `WAIT ..., TIMEOUT LBL[...]` timeout backing System/Config item `14 WAIT timeout`. | Local manual `b-83284en-12-01` pages 169, 175, 272, 286, and 350. Robot SNPX readback returned raw `3000` when pendant config was `30.00 sec`, then raw `18000` after manual config change to `180.00 sec`. | For the current A_MAIN planning contract, a 180 second timeout means `$WAITTMOUT=18000`, not `180`. Any generated write must be explicit and immediately before the bounded `WAIT` it supports. |
| `$SNPX_PARAM.$VERSION` | SNPX protocol/version probe used to verify the FANUC SNPX endpoint. | Project SNPX private ASG readback on a configured controller returned raw `2`. Current read maps use this as a nonzero/expected endpoint probe. | Read-only probe only. Do not write. |
| `$SNPX_PARAM.$NUM_CIMP` | SNPX multi-connection/CIMPLICITY capability probe. | Project SNPX private ASG readback on a configured controller returned raw `4`. | Read-only probe only. Do not write. |
| `$SNPX_ASG` | Per-connection SNPX assignment table mechanism used by `CLRASG`/`SETASG` to project FANUC items into GE-style `%R` words. | Project live SNPX reads and writes have succeeded through private per-connection ASG setup and readback. See `docs\SNPX_READONLY.md`, `docs\SNPX_WRITES.md`, and `docs\SNPX_IMPLEMENTATION_NOTES.md`. | Tooling may use private per-connection ASG setup for reviewed reads/writes. Do not treat ASG mappings as persistent robot configuration. |

## WAIT Timeout Notes

Local manual support:

- `b-83284en-12-01`, page 169: `WAIT timeout` is the period used by conditional
  wait instructions with `TIMEOUT LBL[...]`; default shown as 30 seconds.
- `b-83284en-12-01`, page 175: System/Config item `14 WAIT timeout` is shown as
  `30.00 sec`.
- `b-83284en-12-01`, page 272: conditional waits use `TIMEOUT, LBL[i]`; omitted
  timeout processing waits indefinitely.
- `b-83284en-12-01`, page 286: parameter instructions can assign numeric system
  variables using `$(SYSTEM VARIABLE NAME)=value`.
- `b-83284en-12-01`, page 350: `WAITTMOUT` appears in the system-variable
  selection menu.

Controller evidence:

```text
Before pendant change:
  $WAITTMOUT raw = 3000
  interpreted = 30.00 sec

After pendant change to 180 sec:
  $WAITTMOUT raw = 18000
  interpreted = 180.00 sec
```

Conclusion: this controller stores `$WAITTMOUT` in hundredths of a second.

## Open Checks

- Before generated LS writes `$WAITTMOUT`, compile and round-trip a small no-motion
  proof that uses `$WAITTMOUT=18000` and a bounded `WAIT`.
- Decide whether generated programs should restore the previous `$WAITTMOUT` value
  after each bounded wait, or whether project policy owns it as a fixed cell-level
  setting.
