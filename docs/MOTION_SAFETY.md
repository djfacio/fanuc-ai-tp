# Motion Safety Model

Motion generation is supported only by narrow reviewed templates. The first supported path is `tools\New-FanucMotionLsFromSpec.ps1` with template `pr-waypoint-sequence-v1`.

Before motion is added, a motion spec must capture and review:

- Program purpose and cell context.
- Robot model, controller, payload, and end effector.
- UFRAME and UTOOL numbers, names, and provenance.
- Position source: taught point, PR, CAD/CAM source, or generated coordinate.
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

## Blocked Until Separate Review

- DCS edits.
- Payload changes.
- Mastering changes.
- Frame/tool writes.
- Position-register writes.
- Generated Cartesian `/POS` records.
- System variable writes.
- Background tasks.
- Production program calls.
- Robot-side KAREL/socket services.
