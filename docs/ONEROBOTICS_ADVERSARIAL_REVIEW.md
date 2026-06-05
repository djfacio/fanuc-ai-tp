# OneRobotics Adversarial Review

This is an adversarial review of
`docs/ONEROBOTICS_PRACTICES_COMPARISON.md` against our emerging project rules.
The purpose is to prevent a respected external style guide from becoming an
unexamined rulebook.

## Review Position

OneRobotics is a strong influence, especially for pendant readability,
conventions, refactoring, and avoiding label-heavy TP. It should not become a
blanket authority for generated AI robot code. Our project has additional
requirements:

- deterministic generation
- machine-checkable resource policy
- explicit state/transition evidence
- upload/readback evidence
- operator-owned physical verification
- readable pendant code
- fast iteration

The correct move is selective adoption.

An independent adversarial agent review agreed with the overall conclusion and
added one important constraint: the zero-success convention must not silently
break the staged `TSKSTATUS` and migrated `A_` contracts that currently use
`200/204/404` and `R[94]=200`. Those are compatibility contracts until a
versioned replacement is generated and reviewed.

## Findings

### Finding 1: Zero-success return codes are right, but the rule must separate operation result from observed state.

Severity: High

OneRobotics supports `0` as normal/success and nonzero as abnormal/error. That
is the right default for generated TP/KAREL. The risk is that our proposed code
list still mixes return values from two different layers:

- Did the helper/phase call complete successfully?
- What state did the target task/cell/device report?

Example: `TSKSTATUS` can successfully query a task that is running. If `R[91]`
means "tool call result", then running should not be a nonzero error. If `R[91]`
means "reported task state", then `20 RUNNING` is fine, but it is not the
helper's success/failure result.

Recommended action:

- Use `0 = OK` for phase/helper execution result.
- For query helpers, explicitly document whether the output register contains
  query result or observed state.
- Prefer two-register outputs for rich queries when needed:
  - `R[n] = tool/result status`
  - `R[n+1] = observed task/device state`
- Treat existing `TSKSTATUS`/staged `A_` programs using `200/204/404` as legacy
  compatibility contracts until replaced by a versioned helper or adapter.

Impact on current rules:

- Keep zero-success as the generated default.
- Add a rule that status contracts must define the layer: result, state, or
  detail.

### Finding 2: "Short and focused" can become over-fragmented TP.

Severity: Medium

The OneRobotics advice is right: large TP programs are painful on the pendant.
But generated code can overreact by creating many tiny routines where the
operator has to open program after program to understand one transition.

Recommended action:

- Keep `A_MAIN` compact.
- Extract logic only when the call name and preceding remark preserve the story.
- Allow two or three operational lines inline when they are the transition.

Impact on current rules:

- Our existing rule "encapsulation even for two or three lines if it improves
  auditability" is better than "extract everything."

### Finding 3: Isolating waits is good, but it can hide handshake ownership.

Severity: High

External waits with timeout handling are good candidates for `A_WAIT_*`
routines. The danger is hiding the full handshake contract from the state
coordinator. For example, CNC/TI sync is not just "wait for input"; it is:

- request/ready signal observed
- station action performed
- acknowledgement pulsed
- request-drop wait confirmed
- timeout/fault behavior defined
- WIP mutation delayed until success

Recommended action:

- Extract waits only when the wait routine owns exactly one named contract.
- The caller must still show the state transition and status check.
- Handshake routines may be better named `A_SYNC1_WAIT_READY` or
  `A_CNC_WAIT_READY` than generic `A_WAIT_SYNC1`.

Impact on current rules:

- Strengthen the wait rule: extracted wait routines must declare what handshake
  edge they prove.

### Finding 4: OneRobotics' label conventions should not override our status-code convention.

Severity: Medium

OneRobotics uses HTTP-inspired label conventions such as `LBL[404]` and
`LBL[5XX]`. Separately, OneRobotics recommends `0` for success return status.
Those are not the same kind of convention.

Recommended action:

- Do not use `404/500` as generated return codes by default.
- Label ranges may still use project-local conventions if they are reviewable.
- Prefer named remarks and categorized labels over clever numeric meaning.

Impact on current rules:

- Our corrected return-code rule is sound.
- Add a distinction: label numbering conventions and return-code conventions
  are separate.

### Finding 5: `END` is preferred, but shared cleanup/fault exits remain legitimate.

Severity: Medium

OneRobotics is right that `JMP LBL[999]` is a poor substitute for `END`.
However, generated robot programs often need shared cleanup:

- turn off request output
- preserve/clear WIP intentionally
- write status
- show alarm/message
- close a socket/file
- release a lock

Recommended action:

- Use `END` for simple termination.
- Use fault/cleanup labels only when they perform visible cleanup.
- Do not use normal finish cleanup for fault exits unless that is explicitly
  intended.

Impact on current rules:

- Matches our existing separation between normal finish and fault path.

### Finding 6: KAREL black-box cost is real, but avoiding KAREL too strongly would be a mistake.

Severity: Medium

The OneRobotics KAREL article correctly notes that `.PC` is not pendant-visible
like TP. But our workflow should not turn that into "KAREL only as a last
resort." KAREL is appropriate for reusable functions that TP cannot express
cleanly:

- task introspection
- file parsing
- structured logging
- socket protocols
- math/data manipulation
- utilities with stable TP call contracts

Recommended action:

- Keep production sequencing and motion TP-visible.
- Use KAREL for narrow, tested utilities with stable TP interfaces.
- Require source, compile evidence, and a test/proof harness for reusable KAREL.

Impact on current rules:

- Our `TSKSTATUS` direction is good.
- Future KAREL should be treated like a library, not hidden application logic.

### Finding 7: Robot Server metadata tooling is promising, but availability and security are controller/project dependent.

Severity: Medium

OneRobotics tools reinforce Robot Server/HTTP metadata access. That does not
mean every project can rely on it. Robot Server endpoints, KAREL HTTP unlock,
controller version, and network/security policy can differ by controller.

Recommended action:

- Keep Robot Server as preferred metadata path when available.
- Require capability discovery in each project pack.
- Keep alternative metadata paths possible.

Impact on current rules:

- Our controller inventory and interface strategy documents already support
  this. The OneRobotics comparison should not imply Robot Server is universal.

### Finding 8: Spreadsheet/data-map practices align with us, but Excel should not become the only source of truth.

Severity: Medium

fexcel shows the value of external human-reviewable robot data maps. But this
project also needs schema validation, generated evidence, diffable text, and
automation-friendly config.

Recommended action:

- Use human-reviewable maps.
- Prefer schema-backed text configs/specs as the canonical project source.
- Allow spreadsheet import/export as a convenience layer, not the only contract.

Impact on current rules:

- Our project-pack config approach remains stronger for AI generation.

### Finding 9: "Keep generated LS close to normal TP" conflicts with high-level state-machine tooling if implemented poorly.

Severity: High

OneRobotics' TP+ lesson is important: if the source language is too far from
runtime TP, debugging gets painful. Our state-machine models/specs must not
produce TP that feels foreign or impossible to inspect on the pendant.

Recommended action:

- Keep the state machine in docs/spec/generator evidence.
- Emit normal-looking TP with named routines and visible transitions.
- Include transition tables in review packets.
- Do not generate a giant computed state dispatcher unless the project
  explicitly asks for that architecture.

Impact on current rules:

- State machines are preferred for orchestration models, not necessarily as a
  literal giant TP `SELECT` block.

### Finding 10: Useful alarms must not become verbose pendant clutter.

Severity: Low

OneRobotics encourages actionable error messages. Our generated programs also
use `--eg:` remarks before calls. If uncontrolled, this can make pendant review
too noisy.

Recommended action:

- Use remarks to explain transitions and calls.
- Put detailed diagnostic material in alarm text, user messages, docs, or
  review packets.
- Avoid repeating full status-code dictionaries inside every program.

Impact on current rules:

- Matches the user's previous direction: compact remarks, detailed status
  explanation in KL/docs.

## Accepted Rules

These OneRobotics-aligned rules should be accepted as project direction:

1. Use `0 = OK` for generated TP/KAREL result codes.
2. Keep `A_MAIN` as a compact coordinator.
3. Avoid arbitrary `JMP`/`LBL` flow.
4. Prefer `END` over jump-to-end labels when no cleanup is needed.
5. Use focused routines for waits, IO actions, and reusable conditions.
6. Keep generated `.LS` readable as normal TP.
7. Use external human-reviewable maps for robot metadata.
8. Treat `RUN` as true concurrency requiring ownership policy.
9. Keep KAREL utilities narrow, tested, and source-controlled.

## Modified Rules

These rules should be adopted only with constraints:

| Source Idea | Modified Project Rule |
| --- | --- |
| Keep programs short | Keep main/coordinator programs short, but do not fragment transitions so much that the operator has to chase trivial calls. |
| Isolate waits | Isolate external waits only when the wait routine proves one named handshake edge and returns a clear status. |
| Use conventions | Use project-pack conventions, not a universal register/label scheme. |
| Use Robot Server metadata | Prefer Robot Server when discovered and verified for that controller/project. |
| Use named variables/constants | Use schema-backed maps/specs as canonical source; spreadsheet-style tools may be import/export conveniences. |
| Use state machines | Use state machines as orchestration/review models; emit normal TP rather than opaque dispatch code. |

## Rejected Or Deferred Rules

These should not become rules as written:

- Do not require every wait to be extracted. Some short waits are clearer inline
  when they are the visible transition action.
- Do not require every two-line condition to be extracted. Encapsulation is only
  valuable when it improves reviewability or reuse.
- Do not standardize HTTP-style return codes for generated TP/KAREL.
- Do not make Robot Server mandatory for all metadata projects.
- Do not make KAREL the default place for workflow logic.

## Required Rulebook Updates

The current `STANDARDS_RULES.md` has been updated to reflect the biggest
corrections:

1. Add that every status contract must identify whether a value is an execution
   result, observed state, or detail code.
2. Add that extracted wait routines must prove a named handshake edge.
3. Add that state-machine generation should preserve normal-looking TP and
   include transition tables as review artifacts.
4. Add that Robot Server metadata is preferred only when project capability
   discovery confirms it.

Additional carry-forward note:

- OneRobotics practices can inform style, but generator-enforced behavior must
  still pass this project's standards, FANUC/manual/controller evidence where
  relevant, MakeTP/PrintTP round-trip, and project policy review.
