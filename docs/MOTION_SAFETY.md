# Motion Safety Model

Motion generation is intentionally not supported by the current generator.

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
- T1/manual pendant verification plan.

Motion specs should be rejected by default unless every required field is explicit and reviewed.

## Generator Boundary

The first motion generator should support only reviewed templates with known frames/tools and named taught points or reviewed PRs. It should not generate arbitrary Cartesian motion from natural language.

## Blocked Until Separate Review

- DCS edits.
- Payload changes.
- Mastering changes.
- Frame/tool writes.
- System variable writes.
- Background tasks.
- Production program calls.
- Robot-side KAREL/socket services.
