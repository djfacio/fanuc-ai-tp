# Motion Safety Model

Motion generation is supported only by narrow reviewed templates. The first supported path is `tools\New-FanucMotionLsFromSpec.ps1` with template `pr-waypoint-sequence-v1`.

Before motion is added, a motion spec must capture and review:

- Program purpose and cell context.
- Robot model, controller, payload, and end effector.
- UFRAME and UTOOL numbers, names, and provenance.
- Position source: taught point, PR, CAD/CAM source, or generated coordinate.
- Offset PR source and ownership: manually taught, human-provided for tool
  population, calculated, or imported from another reviewed source.
- Coordinate convention and units.
- Motion type: joint, linear, circular, or process-specific.
- Speed, termination, CNT/FINE, acceleration assumptions, and override assumptions.
- Approach, retract, clearance, and recovery behavior.
- Collision assumptions, DCS boundaries, fixtures, tooling, and operator location.
- IO interlocks, wait conditions, and failure handling.
- RoboGuide verification evidence.
- Operator-owned physical verification plan.

Motion specs should be rejected by default unless every required field is explicit and reviewed.

## Generator Boundary

The first motion generator supports only reviewed PR waypoints:

- `UFRAME_NUM` is selected from the reviewed spec.
- `UTOOL_NUM` is selected from the reviewed spec.
- `PAYLOAD[n]` is selected from the reviewed spec.
- Motion lines reference existing reviewed `PR[n]` targets only.
- Supported moves are `J PR[n]` and `L PR[n]`.
- Supported terminations are `FINE` and reviewed `CNT`.

It must not generate arbitrary Cartesian motion from natural language.

It must not emit `/POS` records for generated taught points in this first template. Position creation, PR writes, frame/tool writes, and CAD/CAM coordinate import require a separate reviewed template.

Offset PRs are human-owned configuration unless a project says otherwise. That
does not mean tooling can never help: when appropriate, the generator should ask
for the offset values, produce a reviewable offset list, and populate those PRs
only through an approved PR-population template or tool. The reviewed human
input remains the source of truth.

For generated motion, prefer calculating explicit approach/safe/retract PRs in a
`CALC_POS`-style TP routine before motion consumes them. This keeps the derived
positions visible and manually movable from the teach pendant. Inline
`Offset,PR[]` and `Tool_Offset,PR[]` motion options remain allowed when the
project specifically needs them, but they are not the default architecture.
Default PR calculation timing is once near startup or at the beginning of the
owning phase. Recalculate during every cycle only for dynamic targets such as
vision, recipe, measured, or conveyor-derived positions.
Generated tools may read PRs for planning and evidence. PR writes require
explicit confirmation and a reviewed PR family/write contract before generation
or controller write execution.
When a PR-population tool needs a Cartesian zero offset vector, keep the
`PR[x]=LPOS-LPOS` technique available as a reviewed implementation detail before
writing individual PR elements.

## Breadcrumb Auto-Home TP Contract

Breadcrumb-based auto-home programs may be generated only as pendant-reviewed
or HMI-started recovery aids after the project approves the route and start
conditions. The breadcrumb must mean reviewed route progress, not "current robot
position". With `FINE` termination it may normally correspond to a reached
target in the reviewed path; with `CNT` termination it must be treated as
advance-run progress only. A generated auto-home routine must:

- force the reviewed low-speed override as the first executable instruction
  before any branch, call, or motion can run;
- include a short reviewed instruction boundary after the override command,
  currently `WAIT .10(sec)` for the `A_MAIN` auto-home experiment;
- write the breadcrumb immediately after each reviewed motion statement;
- use an approved register/comment contract, currently `R[95:Last Motion PR]`
  for the `A_MAIN` mirror experiment;
- route by reviewed PR families and explicit safe-point chains;
- prefer direct `JMP LBL[R[n]]` breadcrumb dispatch with reviewed route-entry
  labels when that makes the pendant program read like a compact recovery map;
- favor route-chain fallthrough from the actual breadcrumb label over synthetic
  full-family alias tables, unless the project explicitly wants full invalid
  label coverage;
- use shared route labels over repeated one-off dispatch branches when that
  improves pendant readability;
- move at a conservative reviewed speed and default auto-home route motion to
  `FINE` termination;
- preserve reviewed linear approach/action geometry when backing out; if the
  source route used `L` motion between an action PR and approach/safe PR, the
  auto-home route should normally use `L` motion back to that approach/safe PR;
- express linear auto-home recovery speed in `mm/sec`, using 10 percent of the
  slowest reviewed source linear speed for that target PR unless a project
  defines a different low-speed conversion;
- refuse known invalid breadcrumb values without motion; unexpected in-range
  corrupted breadcrumb values may rely on the native FANUC missing-label alarm
  when the project explicitly accepts that compact-code policy;
- never release parts casually during auto-home; gripper, vacuum, clamp, or
  part-release outputs require explicit route-level WIP policy;
- document that mid-motion stops require human pendant judgment.

The HMI/operator override setting must not be the only speed-control assumption
for an automatically started auto-home routine. The generated program must set
its own reviewed override before route selection.

The reusable template contract is recorded in `docs\PROGRAM_TEMPLATES.md` under
`Auto-Home Recovery TP`. Keep project-specific route maps and evidence near the
generated job, but keep this speed/breadcrumb/advance-run behavior as the
default future auto-home strategy.

Do not treat a breadcrumb auto-home routine as a collision-recovery proof.
Because TP execution can advance past motion instructions, a breadcrumb after a
continuous `CNT` motion must be recorded in the auto-home evidence. Its meaning
is route progress, not proof that the robot reached that PR. A project may
accept those breadcrumbs without a blocking manifest gate when the homing route
backs up through previous/route-safe points and the cell owner explicitly owns
robot-side route review before commissioning, such as this project's Constant
Path practice.

Generated auto-home route motion itself should normally use `FINE`. Use `CNT`
inside the recovery route only when the project has a reviewed reason; otherwise
the recovery program should favor stop-point clarity over blended cycle time.

## Blocked Until Separate Review

- DCS edits.
- Payload changes.
- Mastering changes.
- Frame/tool writes.
- Unreviewed position-register writes. Reviewed PR population, including
  human-provided offset PR values, requires a separate approved template/tool
  and readback evidence.
- Generated Cartesian `/POS` records.
- System variable writes.
- Background tasks.
- Production program calls.
- Robot-side KAREL/socket services.
