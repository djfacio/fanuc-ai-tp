# Program Templates

Use constrained templates before open-ended generation. Each template should have a spec shape, safety notes, validation expectations, and optional RoboGuide/manual evidence notes.

## Current Template Families

### No-Motion Diagnostic

Purpose:

- Display an operator message.
- Write marker registers.
- Add concise review comments.
- Optionally toggle reviewed low-risk IO only after explicit approval.
- Keep generated TP comment text to 31 characters or fewer after sanitization.
- Keep every register, IO, and CALL target approved in `config\cell-map.psd1`.

Examples:

- `AI_HELLO`
- `AI_REGDIAG`
- `AI_PRCHECK`
- `AI_FRMTOOL`
- `AI_IODIAG`
- `AI_SNAPSHOT`

### Cell Preflight

Purpose:

- Capture operator-owned setup and path assumptions before generated motion or cell automation.
- Keep motion disabled.
- Keep IO writes disabled.
- Record a marker register so external tools can verify the program ran.

Example:

- `examples\AI_CELLCHK.program-spec.json`

### PR Waypoint Motion

Purpose:

- Emit a deterministic motion sequence through reviewed position registers.
- Select reviewed user frame, user tool, and payload schedule.
- Keep points outside the generated source; the program references existing `PR[n]` targets.

Template IDs:

```text
pr-waypoint-sequence-v1
approach-process-retract-v1
io-motion-sequence-v1
```

Supported output:

- `UFRAME_NUM=n`
- `UTOOL_NUM=n`
- `PAYLOAD[n]`
- `J PR[n] speed termination`
- `L PR[n] speed termination`
- `DO[n]=ON/OFF` only for reviewed `io-motion-sequence-v1` actions

Required before generation:

- User frame and tool frame IDs, names, sources, and verification.
- Payload schedule and gripper assumptions.
- Position registers, names, sources, and verification.
- Speed, termination, approach, retract, clearance, and recovery policy.
- DCS/interlock/operator/fault-handling review.
- Optional evidence notes when useful for the project.
- Operator-owned robot setup and physical run decisions.

Motion templates should not be generated from free-form prompts alone.
