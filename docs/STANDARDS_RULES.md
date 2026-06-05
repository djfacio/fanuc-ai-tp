# Standards-Driven Generation Rules

This is the living rulebook for AI-assisted FANUC TP generation. It exists to
push project decisions toward accepted industrial practice while leaving final
cell-specific decisions to the responsible robot programmer/integrator.

These rules are informed by ISO 10218-1, ISO 10218-2, ISO 12100, ISO 13849-1,
ANSI/RIA/A3 robot safety practice, and normal production robot integration
conventions. They are not a substitute for a project risk assessment, validated
safety design, or the robot/controller manuals.

## Review Posture

- Challenge assumptions that are only true because one person knows the cell.
- Separate "works on this machine" from "defensible for future maintenance".
- Prefer explicit contracts over tribal knowledge.
- Prefer boring, bounded, observable code over compact clever code.
- Treat TP code as production sequencing, not a safety-rated control system.
- Do not weaken a rule silently. Record the exception, owner, reason, and scope.
- Apply `docs\SOURCE_AUTHORITY.md` before converting any manual, bulletin,
  training video, FAQ, ASI resource, community article, or local observation
  into a hard generation rule.
- Treat FANUC Tech Transfer Shorts, FANUC Friday Webinars, ASI material,
  Technical Support FAQ, and CRX application videos as practice and taxonomy
  sources unless the specific controller behavior is confirmed by manuals,
  bulletins, project policy, or local controller evidence.

## Non-Negotiable Boundaries

- Generated `A_` code must never overwrite or mutate the proven `F_` baseline.
- Generated code must not edit DCS, safety I/O, mastering, frames, tools,
  payloads, system variables, UOP, or controller configuration.
- Generated code must not run programs from PC tooling.
- Generated code must not assume robot-side safety. Safety functions belong in
  validated safety-rated hardware/control systems.
- Every project needs its own resource policy. Scratch permissions from one cell
  do not transfer to another cell.

## Program Architecture

- Generated TP must be optimized for human mental-model building, not just for
  syntactic correctness. A pendant reviewer should be able to answer four
  questions locally: what cell concept is this section handling, what condition
  allows it to run, what state/resource changes, and where control goes next.
- Reduce active working-memory load. Do not require the reviewer to remember a
  distant label target, hidden register meaning, previous timeout assignment,
  or prior side effect when a local remark, controller comment, status register,
  or named child routine can carry that information.
- Separate intrinsic cell complexity from avoidable presentation complexity.
  Complex handshakes, WIP logic, and motion constraints may be unavoidable.
  Scattered labels, stale comments, unexplained jumps, and mismatched names are
  generator-created load and must be treated as defects.
- Treat high cyclomatic complexity in pendant-facing TP as a reviewability
  defect, not only a software metric. When one routine mixes ownership checks,
  device commands, retry policy, recovery selection, cleanup, and alarms, split
  by decision purpose before upload unless the project explicitly accepts that
  dense shape for a short-lived diagnostic.
- Favor recognition over recall. Use station-literate program names, controller
  resource comments, visible section remarks, and local wait/status contracts so
  the reviewer recognizes intent while standing at the pendant.
- Use chunking deliberately. A child routine is valuable when its name lets the
  reviewer collapse several low-level instructions into one reviewed cell
  concept. A child routine is harmful when it forces the reviewer to leave the
  current program only to discover a generic assignment, one-off test, or
  syntax wrapper.
- Minimize task switching during review. Decomposition should put related
  facts together: call intent, required preconditions, state writes, status
  contract, and fault outcome. Do not split these across multiple files unless
  the split names a real station, device, motion, calculation, handshake, async
  task, recovery, or policy boundary.
- Generate around a visible "spine and ribs" structure. The spine is the normal
  downward sequence a human reads first. Ribs are clearly named optional
  subsections that return to the spine. Fault labels and timeout labels are
  exits from the spine, not hidden alternate routes through it.
- Prefer structured local blocks for ordinary optional work. If a section means
  "do CNC exchange when F61 or F62 exists", generate that as one named section
  using a readable condition and local `IF ... THEN` blocks where TP syntax
  supports it. Do not express ordinary optional work as a chain of unlabeled
  skip labels.
- A phase routine may have at most one ordinary work-entry label unless it is a
  deliberate loop or retry point. Additional labels should normally be timeout,
  fault, normal finish, or cleanup landmarks.
- Do not use `LBL[999]` as a reflex. Use `END` when a leaf routine reaches its
  natural end. Use a common end label only when multiple paths need a shared
  cleanup/status block or when the label is a reviewable landmark in an
  orchestrator.
- A generated main program is an orchestrator, not a motion bucket. This applies
  to `A_MAIN`, `MAIN`, or any equivalent entry-point program in generated TP
  projects.
- Generated main programs should read like a flow chart on the pendant. Prefer
  named child routines for small reviewable phases, even when the child routine
  contains only two or three operational lines, if that makes the workflow easier
  to audit.
- Generated TP should have a visible linear spine: startup/setup, main work
  phases, loop/continue decision, normal finish, and fault/cleanup. A reviewer
  should be able to scan downward and understand the normal cycle without
  reconstructing a control-flow graph from scattered labels.
- Generated programs should be station-literate: use device/action/station
  vocabulary that a robot programmer would naturally use on the pendant, such as
  `GET PART`, `LOAD CNC`, `UNLOAD TI`, `PLACE CONVEYOR`, `Ack1`, and `Sync2`.
  Avoid generator-internal names that do not describe cell work.
- A generated orchestrator should expose only the project-level flow: boot,
  permissives, async starts, station phases, loop/finish decision, normal finish,
  and fault handling. Device details, motion, handshakes, and calculations
  belong in named child routines unless keeping them inline makes the flow more
  readable.
- Tiny routines are encouraged when they name stable cell vocabulary that may be
  repeated or changed later: device actions, station actions, handshakes,
  guards, reusable checks, and policy decisions. Avoid tiny routines that only
  wrap basic TP syntax, arbitrary register assignments, unqualified waits, or
  one-off boolean tests; those make the reader chase code without learning a
  cell concept.
- Generated main programs must visibly mark the main loop, loop decision,
  normal finish path, and fault path. A short main program without these visual
  anchors is still not reviewable enough.
- A normal finish after `Finish Work` must leave the robot in a reviewed
  home/perch posture unless the project explicitly documents a different final
  posture. Finish handshakes are not a substitute for final robot posture.
- Startup initialization must not erase robot-held or station-held WIP flags by
  default. Clearing WIP such as robot-held transfer flags, in-machine flags, or
  outfeed-held flags must be an explicit reviewed reset/recovery action with
  operator intent, not a side effect of entering `A_MAIN`.
- A project may explicitly define robot-held gripper state as nonpersistent at
  startup. When that policy is approved, generated startup may clear robot-held
  transfer flags and gripper/vacuum outputs, but the policy must be written down
  and station WIP, such as CNC/TI in-process flags, must still be preserved.
- Startup initialization must also preserve physical hold outputs when WIP flags
  indicate the robot may be carrying a part. Preserving a flag while dropping
  vacuum, grip, clamp, or shutoff outputs is a defect unless the project has
  reviewed evidence that those outputs cannot release WIP.
- If a generated phase physically takes ownership of a part before the final
  station-ready state is proven, it must set a durable intermediate WIP state
  before the next abort/restart point. Do not rely on the fact that two child
  calls normally run back-to-back in one scan.
- Generated main programs should prefer a status-gated flow chain over repeated
  post-call fault jumps when phases share the same normal/fault decision. The
  orchestrator may use conditional phase calls such as
  `IF (<flow_status>=OK),CALL <phase>` so a failed phase naturally skips
  downstream work and falls into the common loop/finish/fault decision. The
  project must name the flow status register/value in its contract. Use explicit
  post-call branches only when a phase has a unique immediate recovery path or
  the branch itself is important to pendant review.
- Labels are allowed and often useful in TP, but generated labels must be
  control landmarks, not arbitrary graph edges. Acceptable labels include loop
  start, guarded section entry, retry/recheck point, timeout/error branch,
  normal finish, common cleanup, and fault exit. Avoid unlabeled forward/backward
  jumps, multiple hidden re-entry points, and computed state-to-label dispatch
  unless the project explicitly chooses a state-machine architecture.
- Every nontrivial generated label must have a nearby pendant-visible remark
  naming its purpose. Label numbers alone are not documentation.
- Generated code should avoid aggressive label jumping inside the normal path.
  Use straight-line sequence, boolean conditions, status-gated calls, and named
  child routines first. Use `JMP LBL[...]` when it improves reviewability:
  loop-back, skip an inapplicable section, exit to a named finish/fault path, or
  handle a timeout/unique recovery branch.
- Generated workflow programs should place a `--eg:` remark immediately before
  every `CALL`. The yellow pendant remark line is a visual guide rail; repeat
  yourself when it makes call chains easier to scan.
- Use `END` when a leaf routine simply needs to end. Keep explicit finish,
  fault, or cleanup labels in orchestrators and phase routines when those labels
  make state outcome, cleanup, or recovery easier to review.
- Station motion belongs in small `A_` routines with one clear responsibility.
- "Single purpose" means one coherent cell task or one coherent logic subsection
  of a wider task, not one TP instruction. Good single-purpose routines name a
  station action, device action, handshake edge, motion/action sequence,
  calculation, async task boundary, guard group, recovery path, or reviewable
  policy decision. Bad single-purpose routines merely wrap arbitrary syntax,
  one-off assignments, or isolated boolean tests that force the reader to chase
  code without learning a cell concept.
- Calculation routines, motion routines, peripheral routines, and async tasks
  must be separated unless the exception is justified.
- No-motion generated TP programs must use `DEFAULT_GROUP = *,*,*,*,*,*,*,*;`.
  Owning a motion group is itself a resource claim and can collide with other
  running tasks even when the `/MN` body has no motion instructions.
- PR writes and PR calculations are motion-affecting resource writes, even when
  the routine has no `J`, `L`, or `C` motion line. FANUC documents PR operations
  as group-mask dependent, and non-motion PR operation requires an explicit
  controller mode. Generated PR calculation routines must use a reviewed motion
  group mask unless a project-specific policy approves that controller mode.
- Unless a project says otherwise, generated PR calculation routines use Group
  1 only. Do not infer authority for additional motion groups.
- Motion-capable generated TP programs must declare only the reviewed motion
  groups they actually need.
- Existing `F_` routines may be called during migration only when listed in the
  project contract and reviewed as a dependency.
- Thin TP wrappers around KAREL `.PC` helpers are integration boundaries, not
  ordinary TP routines. Generated wrappers may own that boundary, but they must
  keep KAREL calls shallow: do not hide a KAREL bridge call behind extra generic
  phase wrappers when the same call can be made directly from the owning phase.
  The wrapper contract must name the KAREL helper, arguments, result registers,
  close/cleanup path, and expected maximum caller depth.
- Do not assume a fixed normal TP `CALL` nesting level. FANUC documents
  `INTP-302 Stack overflow` as a stack-budget problem: recursion, many `CALL`
  instructions, KAREL calls, and local registers all consume stack. For
  generated entry chains that call KAREL helpers, treat `500` as the default
  first check; after a confirmed `INTP-302`, raise the reviewed main caller and
  direct bridge wrappers to `1000` before adding more wrapper depth. Keep this
  separate from the documented `FOR`/`IF_THEN` nesting limit of 10 and the
  pendant edit navigation limit for drilling through called subprograms.
- When migrating or learning from legacy TP, do not treat nearby comments,
  branch labels, or alarm text as the only source of signal meaning. If legacy
  text conflicts with controller-resident comments, the reviewed cell map, or
  live read-only evidence, generated code must stop and resolve the discrepancy
  in the project rule/spec before emitting operator-facing messages or alarms.
- Every generated program must declare:
  - purpose
  - inputs
  - preconditions
  - touched frames, tools, payloads, PRs, registers, flags, I/O, and calls
  - success criteria
  - failure behavior
  - recovery/restart assumptions
- Program declarations and review packets must identify which rule source class
  supports important behavior: project policy, manual/bulletin, local evidence,
  training-derived practice, or advisory external practice.

## Diagram And Review Artifacts

- TP workflow/program-flow diagrams should use PlantUML activity diagrams as
  the editable source of record. PlantUML matches the normal robot-programming
  thought process better than box-first layout tools: sequence, guard, branch,
  call, loop, and fault path.
- PlantUML diagrams should read like the intended TP spine: startup, main loop,
  station phases, finish-work decision, normal finish, and fault/recovery exits.
  If the diagram does not help a reviewer write or read the TP program, fix the
  diagram before treating it as design evidence.
- Use Graphviz DOT for audit views where layout should expose dependencies,
  branch density, call graphs, complexity, or orphan paths.
- Use D2 for compact state, dependency, and system maps when it stays readable.
  Do not use D2 as the default TP workflow diagram format when PlantUML better
  expresses the sequence.
- Use Mermaid only for lightweight Markdown sketches, issue comments, and quick
  communication. It is not the source of record for generated TP workflow
  reviews unless a project explicitly chooses it.
- Use diagrams.net/draw.io for manually polished presentation diagrams or
  customer-facing cleanup. It should not be the canonical generated source
  unless the project accepts manual diagram maintenance.
- Use a cheap draft-review gate before generating polished artifacts. For normal
  iteration, review the PlantUML source and, when useful, one rendered SVG/PNG.
  Do not generate all candidate formats or a PDF unless the team is choosing a
  diagram technology, freezing a reviewed design packet, preparing a handoff, or
  explicitly requesting a printable artifact.
- Every generated diagram packet should keep the editable source, rendered SVG
  or PNG, and PDF review output together so pendant review, design discussion,
  and future regeneration stay connected.

## State And Recovery

- A real application must have an explicit WIP/state model.
- Pendant-facing generated TP/KAREL result codes should use zero-success
  automation/software convention by default: `0` for OK/normal completion,
  nonzero for no-work, running/busy, guard failure, timeout, not-found, bad
  argument, unavailable dependency, or failure. HTTP-like codes may be used for
  PC-side tools, Robot Server wrappers, legacy utilities, or a documented
  project exception, but they are not the default for generated robot programs.
- Do not invent opaque status numbers. Generated status values must have stable
  names in the project contract and must be visible in review docs/comments
  where they affect a transition.
- Every status contract must identify the layer it represents: phase/helper
  execution result, observed task/device/cell state, or detail/diagnostic code.
  Do not silently mix these layers in one register. Query helpers that need both
  result and observed state should use separate documented outputs.
- Coarse flow status and detail status should be separated when a generated
  program has more than one failure reason. The flow status should answer "what
  does the orchestrator do next?", while the detail status should answer "what
  exactly failed?". Do not mirror one vague value into both registers when
  unique detail codes would make pendant review and recovery easier.
- Existing staged utilities and review programs that still use earlier
  HTTP-style contracts, such as `TSKSTATUS` returning `200/204/404`, are legacy
  compatibility contracts until a versioned replacement or adapter is generated,
  uploaded, and reviewed with matching pendant remarks and manifests.
- Current `A_MAIN` greenfield review drafts may temporarily keep the existing
  `R[80]=200` continue, `R[80]=204` Finish Work complete, and `R[94]=200`
  transfer-success contracts while the structure is being reviewed. Generated
  docs must label this as a compatibility exception, not the default rule for
  future projects.
- The default generated TP/KAREL status set is: `0 OK`, `1 NO_WORK`,
  `10 ACCEPTED`, `20 RUNNING`, `30 HELD`, `40 BUSY`, `50 GUARD_FAILED`,
  `60 TIMEOUT`, `70 NOT_FOUND`, `80 BAD_ARG`, `90 UNAVAILABLE`,
  `100 FAILED`, and `999 UNKNOWN`.
- Flags may mirror state, but they must not be the only undocumented state model.
- Every state transition must define what proves the transition succeeded.
- Failure handling must preserve enough WIP state for a human to recover safely.
- Restart behavior must be specified for power-up, abort, fault reset, and manual
  intervention.
- `F_INIT`-style startup code must document which state is reset, which state is
  preserved, and why.

## Waits And Handshakes

- External-device waits must be bounded unless a reviewed exception says why an
  indefinite wait is acceptable.
- A bounded wait must define timeout duration, alarm/status code, outputs to set
  or reset, and WIP state behavior.
- Extracted wait routines must prove one named wait or handshake edge and must
  declare touched I/O, timeout value, return codes, alarm/message behavior, WIP
  preservation, cleanup ownership, and what transition the caller should take on
  success/failure. Avoid generic reusable waits for cell-specific handshakes.
- Handshakes must be paired: request, ready/complete, acknowledgement, timeout,
  and reset/clear behavior should be visible.
- One-shot pulses are allowed only when the receiving device's edge/level
  expectation is documented.
- Time waits used for mechanical settling must be named by purpose in the spec.

## Motion Rules

- Every motion routine must set or inherit reviewed `UFRAME_NUM`, `UTOOL_NUM`,
  and payload schedule intentionally.
- Approach, process, and retract points must be explicit.
- Generated motion routines should use a predictable pendant shape: set
  frame/tool, move to approach or safe PR, move to process/work PR, perform the
  device action or proof, then retract. Repeating `UFRAME_NUM` and `UTOOL_NUM`
  before motion blocks is acceptable when it improves pendant readability.
- Shared safe points must be named and justified by station context.
- FINE/CNT termination must be chosen deliberately, not copied mechanically.
- Speeds must have policy: approach, process, retract, and recovery speed.
- Automatically started generated recovery programs, including HMI-started
  auto-home, must set the reviewed low-speed override as the first executable
  instruction before any branch, call, route-selection logic, or motion can run.
  Add a short reviewed instruction boundary after the override command when the
  program relies on the override before motion.
- Generated auto-home should default to a route-chain or funnel-to-safe-point
  architecture: enter from the last reviewed breadcrumb, move through the next
  station clearance point, then reuse shared safe/home landmarks. Do not
  generate direct-home-from-anywhere motion unless the project proves that every
  allowed start posture can safely take that move.
- Generated auto-home route motions should use `FINE` termination by default.
  `CNT` in recovery motion is an explicit project exception, not the normal
  generated style.
- Generated auto-home must not convert reviewed linear approach/action geometry
  into joint motion by default. When an action PR and approach/safe PR are part
  of a reviewed linear process segment, back out with `L` motion to the
  approach/safe PR unless the project documents why a joint escape is safer.
- Linear auto-home recovery speed should be emitted in `mm/sec`. Use 10 percent
  of the slowest reviewed source linear `mm/sec` speed for that target PR unless
  the project defines another low-speed conversion.
- Reference-position, DCS, zone, LPOS, or similar current-position checks are
  optional guard layers for auto-home, not substitutes for a reviewed route.
  Add them when they answer a specific recovery question; avoid generic checks
  that increase pendant complexity without changing the route decision.
- Generated motion should reference reviewed PRs first. Direct Cartesian
  generation requires a stricter reviewed policy.
- Offset PRs are human-owned configuration by default, meaning the responsible
  robot programmer/integrator owns the value and approval. Generated tooling may
  still ask for offset values, create a human-reviewable offset list, and
  populate those reviewed values when the project policy explicitly grants PR
  population authority. After population, treat those offset PRs as locked
  reviewed inputs until the human owner revises them.
- Prefer explicit calculated approach/safe PRs over inline motion modifiers when
  practical. A `CALC_POS`-style routine should calculate derived approach,
  safe, and retract PRs at the beginning of the cycle or phase so those
  positions are visible on the teach pendant and available for manual
  `MOVE_TO`/touchup/review operations. Use `Offset,PR[]` or `Tool_Offset,PR[]`
  only when the project has a clear reason, such as repeated pattern motion,
  process/tool-relative adjustment that should stay inline, or a controller
  behavior that is easier to review that way.
- Default calc timing is once near startup or at the beginning of the owning
  program/phase. Recalculate every cycle only when the point is dynamic, such as
  a vision, recipe, conveyor, or measured input target, or when the project
  explicitly wants cycle-by-cycle recalculation.
- Generated tools may read PR values for analysis, review packets, diffs, and
  evidence, but reads must be recorded when they inform generated behavior. PR
  writes are never implied by read access; request explicit confirmation before
  writing or generating code that writes a PR.
- Programs that calculate or overwrite PRs must define PR ownership and
  concurrency rules. Use `LOCK PREG` or an equivalent reviewed exclusion policy
  when another task could read or move to the same PRs.
- Vacuum/grip actions must have a proof of success where available. If no sensor
  exists, that absence must be explicit.
- Motion routines must declare PR ownership, including who writes the PRs, who
  may read/move to them, whether another task can observe them, and whether a
  `LOCK PREG` or equivalent exclusion policy is required.
- `LOCK PREG` is not a default requirement in this workframe. Use it only when
  PR concurrency is real or credible, such as async tasks, background logic, or
  another motion program reading/moving to PRs while they may be rewritten.
- Generated code should not casually change offset PRs during production
  sequencing. Runtime PR calculation may combine reviewed base/work PRs and
  reviewed offset PRs into derived approach/safe PRs, but the offset PR itself
  remains a reviewed configuration resource unless the project explicitly marks
  it as calculated.
- When a generated tool must create or reset an offset-vector PR, keep the
  `LPOS-LPOS` Cartesian-zero pattern available as a reviewed implementation
  technique before writing individual PR elements. Do not use the trick
  blindly; document the representation intent and verify the resulting PR by
  readback or pendant review.
- Motion routines must return an explicit success/failure result before callers
  mutate WIP flags. A caller may not mark a part transferred, clear a station
  WIP flag, or advance the application state only because a `CALL` returned.
- Project WIP definitions decide when a flag should clear. For example, if a
  flag means "part is held by the robot gripper for print," then dropping the
  part to the conveyor is the correct point to clear that robot-held flag; do
  not misclassify that as station WIP loss.
- For robot-held WIP flags, prefer clearing the flag in the routine that owns
  the physical release, immediately after the reviewed release instruction and
  before unrelated downstream async handling. Downstream conveyor/marking/etc.
  failures may be separate faults, but they should not make a gripper-held flag
  claim the robot still has a part after the release has occurred.
- Breadcrumb registers written after motion must account for TP advance-run
  behavior. A post-motion breadcrumb after `FINE` motion may represent a
  completed target for the reviewed program, but a post-motion breadcrumb after
  `CNT` motion must not be treated as completed-target evidence. It is a
  route-progress marker that may have advanced before the robot physically
  reached the PR. Auto-home may still use that breadcrumb when the reviewed
  route-chain intentionally backs up through the previous/route-safe path.
- Generated auto-home programs may rely on the native FANUC missing-label alarm
  for unexpected in-range corrupted breadcrumb values when a project accepts
  that compact-code policy. Use explicit no-motion guards for zero, out-of-range,
  and known unused route labels.
- Generated auto-home programs must not casually release parts. Any gripper,
  vacuum, clamp, or output action that can release WIP inside a homing route
  requires explicit route-level WIP policy and cell-owner step review.
- Every generated motion routine must have a reviewable contract covering:
  frame, tool, payload, PRs, approach, process, retract, speed policy,
  termination policy, success proof, failure behavior, restart assumptions, and
  group-mask/resource claims.
- Generated PR and register comments are part of pendant readability. Named
  points like `LOAD_CNC_APP`, `BOWL_PICK`, or `JCONVSAFE` are easier to review
  than bare `PR[91]`; bare resources require a local explanation or a generated
  controller comment plan.
- Motion template design should use application-pattern vocabulary when useful:
  machine tending, palletizing, dispensing, welding, inspection, vision pick,
  conveyor/RTU, handshaking, PLC/HMI controlled operation, and finish-work
  operation. These patterns shape templates; project policy still controls
  resources.

## Async Tasks

- `RUN` is blocked by default for generated code until an async-task contract is
  reviewed.
- Async tasks must have single-instance protection, heartbeat/status, ownership
  of shared flags/registers, and a defined stop/fault behavior.
- A main program must not blindly start a task that might already be running.
- Generated async starts should go through a narrow wrapper such as
  `A_FSTART`/`A_CSTART`: call `TSKSTATUS`, allow only the reviewed inactive
  states to start, issue the `RUN`, then confirm the task reached the expected
  running state or alarm.
- If a task owns a software busy flag for an output pulse or timed action, keep
  the busy flag true until the output/action is observed inactive. A pulse
  instruction followed immediately by `Busy=OFF` is not an acceptable ownership
  model for generated async code.
- Async owner routines should read as one clear loop: prove the owning task is
  still allowed to run, call one named unit of work, interpret its result, then
  stop or repeat. Sensor/scan work, retry counters, feed/recovery choices, and
  close/alarm exits should become named helpers once they make the owner harder
  to scan on the pendant.
- Async helper result registers must not collide with the main phase result
  contract. In the current `A_` compatibility set, `R[94]` belongs to
  caller/callee transfer success; feeder async helpers use the feeder task
  status/result register instead.
- Background logic, macro starts, PNS/RSR/UOP starts, and HMI/PLC starts must be
  included in dependency and recovery discussions.

## Naming And Resource Conventions

- Generated programs use `A_`.
- Existing `AI_` programs are legacy generated artifacts only.
- Generated prefixes are project policy, not a permanent architecture. The
  current project uses `A_` for new generated programs and recognizes legacy
  `AI_`; future projects may choose a different generated prefix and must update
  specs, validators, cleanup policies, and review docs together.
- Production baseline programs such as `F_` are read/reference dependencies
  unless explicitly migrated.
- Registers, PRs, flags, I/O, and calls must come from the project cell map or a
  reviewed project-specific policy.
- Project conventions for scratch registers, status registers, PR ranges, IO
  ownership, alarms, and generated prefixes must be machine-validated project
  policy, not prose defaults. Resource conventions from one project never grant
  permission in another.
- Generated IO helper routines must be allowlisted call targets, named by
  device/action, and declare touched DO/DI/RI/RO/GI/GO/flags/registers,
  success proof, restoration behavior, and caller status contract. Do not use
  broad generic IO helpers as a way around resource policy.
- Program comments should follow a visible hierarchy. Use `--eg:`
  multi-language remarks for section headers, phase intent, guard conditions,
  wait contracts, task-status decisions, fault-path reasons, and any explanation
  that benefits from pendant wraparound. Use `!` comments for short local step
  labels, branch labels, and intentionally preserved legacy notes. The two forms
  may appear in the same program, but the distinction must be deliberate.
- Prefer one `--eg:` remark for one related idea, even if it wraps on the teach
  pendant, instead of several consecutive `--eg:` lines. Use consecutive
  `--eg:` remarks only when the ideas are unrelated or each line is a separate
  visual section.
- Blank `/MN` lines are part of generated readability. Use a blank line between
  startup, loop, station phase, loop decision, finish, and fault chunks; also use
  blanks around local motion/action groups when it makes pendant review easier.
- Generated main-loop headers should follow the human style used in the source
  `F_` programs: mixed-case `--eg:` text with a short star tail, such as
  `--eg:Main Loop ********************************* ;`. Avoid decorative
  full-width banner text such as `========== MAIN LOOP START ==========` in
  generated TP.
- Program list comments must use operator language, not generator/debug
  shorthand. Prefer comments such as `Boot Checks`, `CNC Exchange`, or
  `Fault Cleanup` over draft labels such as `GREEN BOOT`.
- Program names and nearby section remarks should use the same project
  vocabulary whenever possible. Do not make the reader translate `A_BOOT` to a
  `Startup` remark or vice versa. Pick the shortest name that still describes
  the task accurately; for cycle permissives/init/feeder startup, prefer
  `A_STARTUP` over `A_BOOT` because boot implies controller power-up behavior.
- Generated human text should use mixed/title case with deliberate acronyms and
  signal names preserved, for example `Ensure CNC is NOT Alarmed`, `Pick Part
  From Bowl`, and `Sync1`. Use all caps only for very short local labels,
  stable acronyms, or alarm-style labels where that improves pendant scanning.
- Set `$WAITTMOUT` immediately before the `WAIT ... TIMEOUT` line that consumes
  it. No blank line, remark, assignment, or unrelated instruction may appear
  between the timeout write and its corresponding timed wait.
- Use boolean expressions to improve human readability when they express one
  domain idea, such as `IF (F61 OR F62)` for "CNC exchange has work". Avoid
  splitting one idea into several jumps unless the split improves pendant scan.
  Also avoid very long combined conditions that wrap into unreadable line noise.
- Prefer pendant-scan-friendly control flow over mechanically generated
  branch-after-every-line patterns. If a generated program contains several
  sequential `IF ...,JMP LBL[...]` branches, the generator should justify why
  each branch is a clear decision point, timeout/recovery path, or named section
  exit.
- Nontrivial generated routines with error labels should visibly separate the
  task body from the fault branches with a `--eg:` section remark such as
  `--eg:Error Section *************************** ;`.
- Put a blank line and a `--eg:` program-end remark immediately before a common
  end label such as `LBL[999]`. Use `END` for a simple terminal path; use a
  common `LBL[999]` when multiple normal/error paths should converge on one
  named end section or may need shared cleanup/status handling later.
- Generated remarks before `CALL` instructions should explain the call contract
  or review decision, not merely repeat the called program name. Good remarks
  say what the callee must prove, which status/register it writes, or what state
  the caller will mutate after return.
- Error labels should have a preceding pendant-visible remark naming the coarse
  status, detail status, and fault meaning, especially when label numbers are
  reused across generated programs.
- Comments should be operational and concise. Avoid empty remarks, stale
  commented-out code, typo-heavy comments, and long banner comments that wrap
  badly on the pendant. Put deeper rationale in specs/review packets, not in the
  TP line list.
- Pendant-facing remarks should not expose generator debt unless the operator
  or reviewer needs it to choose an action. For example, do not write "callee
  has no result contract yet" in a production review program; record that in the
  review packet and use an operational remark such as "pick part from bowl" in
  the TP code.
- Generated code must avoid bare temporary registers, PRs, flags, and IO when
  the controller supports comments. If a generated artifact must use a temporary
  resource, give it a controller comment or a nearby one-line local purpose
  remark.
- Mixed logic may use `!` only directly in front of a single non-grouped
  signal/entity, such as `!F[50:Part_Ready]`. Do not generate grouped negation
  such as `!(A OR B)`. Prefer affirmative sensor and state names like
  `Part_Ready`, `Clamp_Open`, or `CNC_Alarm` over names such as
  `Part_Not_Ready`, so generated conditions do not become double negatives.
- Controller metadata comments such as register comments and IO comments are
  production documentation. Snapshot existing comments and review a diff before
  overwriting them, even when the write does not change IO values.
- State-machine and transition-table artifacts are review/generation evidence.
  Generated `.LS` must still look like normal pendant-reviewable TP with visible
  state names, guards, success proof, and fault branches. Avoid opaque computed
  state-to-label dispatch unless the project explicitly chooses that architecture.

## Evidence Required Before Upload

- Spec validation passed.
- LS safety validation passed.
- MakeTP compile passed.
- PrintTP round trip passed.
- Review packet generated.
- Dependency map reviewed for calls, runs, macros, KAREL `.PC`, and protected
  programs.
- Active commissioning policy recorded; optional per-job review recorded only
  when it adds useful evidence.
- Upload/readback evidence recorded after upload.

## Discussion Rules

- Codex should push back when the proposed design lacks state, timeout,
  recovery, ownership, or evidence.
- The human owner may override a recommendation, but the override must be
  recorded as project policy.
- "I know this cell" is valid input, but the generated project must capture what
  matters so another competent person can maintain it later.
