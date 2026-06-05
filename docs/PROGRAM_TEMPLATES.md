# Program Templates

Use constrained templates before open-ended generation. Each template should have a spec shape, safety notes, validation expectations, and optional RoboGuide/manual evidence notes.

Template rules that affect generated TP/KAREL behavior must follow
`docs/SOURCE_AUTHORITY.md`. Manuals, Engineering Bulletins, project policy, and
local controller evidence can become hard template gates. Training videos,
Tech Transfer Shorts, FANUC Friday Webinars, ASI resources, FAQs, and CRX
application videos are good sources for template ideas and review prompts, but
they are not hard controller-behavior authority until confirmed.

## Current Template Families

### Status-Gated Orchestrator

Purpose:

- Preserve a linear spine for the normal path: startup/setup, named phases,
  loop/finish decision, normal finish, and fault/cleanup.
- Keep the reviewer's active mental state small: each phase should advertise
  its cell concept, precondition, status contract, and next control outcome
  without requiring label hunting.
- Use a spine-and-ribs shape: the normal path reads downward, and optional
  station/device subsections branch locally and return to the phase spine.
- Generate the top-level TP flow as a pendant-readable sequence of named phases.
- Run each phase only while the project flow status is still OK.
- Let any phase stop downstream work by changing the flow status.
- Route all shared loop, finish, and fault outcomes through one visible decision
  section.
- Avoid repeated post-call fault jumps when every phase has the same failure
  destination.
- Keep labels as visible landmarks for loop starts, timeout/error exits, common
  cleanup, normal finish, and reviewed retry/recheck points. Do not use labels
  as arbitrary hidden graph edges in the normal path.

Template shape:

```text
set <flow_status> = OK
call startup/permissives
if <flow_status> <> OK, jump common decision/fault

main loop:
remark phase 1
if <flow_status> = OK, call phase 1
remark phase 2
if <flow_status> = OK, call phase 2
remark loop/finish/fault decision
if <flow_status> = REPEAT, jump main loop
if <flow_status> = DRAINED, jump normal finish
jump fault
```

Use explicit post-call branches instead when a phase has a unique immediate
recovery path, cleanup path, or review-critical branch. If the workflow needs
manual resume states, bypass modes, rework paths, multiple product modes, or
operator-selected modes, consider an explicit state-machine template instead of
this flow-chain template.

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

### Auto-Home Recovery TP

Purpose:

- Return the robot from the last reviewed completed motion target to a reviewed
  home/perch posture.
- Support pendant-started or HMI-started recovery only after the project owner
  approves the route policy and start conditions.
- Keep recovery speed bounded by the generated program itself, not only by HMI
  or operator override state.

Required strategy:

- Use a project-approved breadcrumb register. In the current `A_MAIN` mirror
  experiment this is `R[95:Last Motion PR]`; future projects may choose a
  different documented resource.
- Write the breadcrumb immediately after a reviewed motion statement.
- Treat the breadcrumb as a route-progress marker, never as live current
  posture. With `FINE`, it can normally be read as the reached target in the
  reviewed path. With `CNT`, it may be written before the physical robot reaches
  that PR; recovery must therefore use the route-chain semantics, backing up
  through the previous/route-safe path rather than treating the breadcrumb as a
  pose measurement.
- Generate the auto-home TP so the first executable instruction is the reviewed
  low-speed override. Current convention:

```ls
OVERRIDE=10% ;
WAIT .10(sec) ;
```

- Place those override lines before any route-selection branch, `CALL`, label
  dispatch, frame/tool assignment for motion, or motion instruction.
- Use a short reviewed instruction boundary after the override command so route
  selection and motion cannot be the next instruction in the same execution
  moment.
- Prefer direct breadcrumb label dispatch, `JMP LBL[R[n]]`, when the breadcrumb
  is written only by reviewed motion programs and the homing source defines the
  reviewed route-entry labels.
- Model the homing source as route chains, not as a synthetic alias table for
  every PR in a family. A breadcrumb should enter the remaining safe path from
  that exact label, then move through the next reviewed approach/safe/depart PRs
  before reaching shared station-safe or home landmarks.
- Use minimal invalid-value guards for zero, out-of-range, and explicitly unused
  reviewed labels. A project may accept the native FANUC missing-label alarm for
  unexpected in-range corrupted breadcrumb values. Generate a full invalid-label
  table only when a project chooses diagnostic coverage over the compact homing
  style.
- Avoid long repeated `IF ...,JMP LBL[...]` or large `SELECT` dispatch blocks
  unless they make an important recovery decision more visible.
- Reuse route labels instead of duplicating motion. Common patterns include
  successive route-entry labels, fallthrough chains for ordered safe positions,
  and one or two shared final home landmarks reached by fallthrough or
  `JMP LBL[...]`.
- Use reviewed PR-family route chains, for example station safe point -> shared
  safe point -> home.
- Known invalid breadcrumb values must not move. They must display a clear
  message and/or raise a reviewed User Alarm. Unexpected in-range values may use
  native FANUC missing-label alarm behavior when the project accepts that policy.
- Gripper, vacuum, clamp, or part-release outputs inside auto-home routes are
  not default behavior. They require explicit route-level WIP policy and
  cell-owner step review.
- Auto-home motion should use conservative reviewed speed and `FINE` termination
  by default. Recovery is normally about predictable stop points, pendant
  stepping, and unambiguous route progress, not cycle time. `CNT` in an
  auto-home route is a project-specific exception and must be called out in the
  route evidence.
- Preserve the reviewed motion geometry when backing out of approach/action
  pairs. If the source route used linear motion from approach to action or
  action back to approach, the generated auto-home route should normally use
  `L` motion back to the approach/safe PR rather than converting that segment to
  `J`.
- Linear auto-home recovery moves should use `mm/sec`, not percent speed. The
  default generated equivalent for the current low-speed override is 10 percent
  of the slowest reviewed source linear `mm/sec` speed for that target PR.

Advance-run rule:

- Post-motion breadcrumbs after `CNT` motion must be visible in evidence. They
  mean route progress may have advanced past the physical robot, not that the
  robot reached the PR. They are acceptable when the project explicitly accepts
  route-chain backtracking semantics, for example when the cell owner uses
  Constant Path behavior and owns robot-side route review before commissioning.

Evidence before upload:

- Route map from breadcrumb values to safe-return chains.
- LS safety validation.
- MakeTP compile.
- PrintTP round-trip.
- A scan showing whether any breadcrumb source motions use `CNT`.
- Job manifest gate recording the auto-home evidence class, CNT breadcrumb
  source count, upload status, and upload/readback evidence when present.
- Project approval of HMI start conditions, route families, alarm behavior, and
  low-speed override policy.

## Application Pattern Families

Use these pattern names when planning real applications. They are not templates
by themselves; they are the vocabulary used to choose or design templates.

### Machine Tending

Typical phases:

- wait/load-ready
- pick from source
- unload finished part
- load raw part
- prove clamp/part/station state
- acknowledge handshakes
- drain remaining WIP

Generation pressure points:

- CNC or machine handshake edge/reset behavior.
- Single part ownership between robot, station, and outfeed.
- Finish/drain behavior when infeed is off.

### Palletizing And Depalletizing

Typical phases:

- count or pattern selection
- source proof
- approach/pick/retract
- destination calculation or PR lookup
- place/prove/retract
- layer/pallet completion

Generation pressure points:

- PR calculation ownership.
- Pattern counters and restart state.
- Collision-free approach/retract points.

### Conveyor, RTU, And Outfeed

Typical phases:

- wait conveyor/fixture clear
- move to handoff
- place or release
- prove part departure/arrival
- reset request/ack state

Generation pressure points:

- Conveyor ready and blocked-start behavior.
- Request-drop wait after acknowledgements.
- Optional regrip/recirculation behavior.

### Inspection And Vision Pick

Typical phases:

- start or verify vision/inspection task
- request image/result
- validate result freshness
- transform or select target PR
- pick/process with proof

Generation pressure points:

- Async task ownership.
- Result freshness and stale-result rejection.
- Camera/tool/frame assumptions.

### Dispensing, Welding, Painting, And Process Motion

Typical phases:

- approach
- enable process
- process path
- disable process
- retract
- confirm process completion

Generation pressure points:

- Process IO timing and one-shot/level expectations.
- Speed/termination policy.
- Recovery path when the process starts but the path does not finish.

### PLC/HMI Controlled Operation

Typical phases:

- command source validation
- program/task selection policy
- status/result writeback
- guarded start/stop behavior
- alarm/detail reporting

Generation pressure points:

- UOP/PNS/RSR/macros/background starts must be reviewed as async starts.
- Runtime values should use the approved typed interface, currently SNPX by
  default for register/IO values.
- Generated programs must distinguish command acceptance from operation success.
