# Program Templates

Use constrained templates before open-ended generation. Each template should have a spec shape, safety notes, validation expectations, and a pendant/RoboGuide verification plan.

## Current Template Families

### No-Motion Diagnostic

Purpose:

- Display an operator message.
- Write marker registers.
- Add checklist comments.
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

- Capture an operator-guided checklist before generated motion or cell automation.
- Keep motion disabled.
- Keep IO writes disabled.
- Record a marker register so external tools can verify the program ran.

Example:

- `examples\AI_CELLCHK.program-spec.json`

### Future Motion Template

Required before implementation:

- User frame and tool frame IDs.
- Payload and gripper assumptions.
- Position source and touch-up plan.
- Speed, zone, and termination policy.
- Collision/DCS assumptions.
- RoboGuide pass evidence.
- T1/manual pendant verification notes.

Motion templates should not be generated from free-form prompts alone.
