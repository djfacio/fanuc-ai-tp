# OneRobotics Practices And Current Project Comparison

This note summarizes OneRobotics practices that are directly evidenced from
public OneRobotics articles and GitHub repositories, then compares them with the
current AI-assisted FANUC TP workflow decisions in this project.

This is not a FANUC manual authority document. Treat it as an experienced
integrator/source-code influence document.

## Sources Reviewed

- OneRobotics, "Writing Maintainable TP Code"  
  https://www.onerobotics.com/posts/2014/writing-maintainable-tp-code/
- OneRobotics, "Don't Jump Around"  
  https://www.onerobotics.com/posts/2014/dont-jump-around/
- OneRobotics, "Isolate Your Wait Statements"  
  https://www.onerobotics.com/posts/2016/isolate-your-wait-statements/
- OneRobotics, "Embrace the END Statement"  
  https://www.onerobotics.com/posts/2016/embrace-the-end-statement/
- OneRobotics, "Refactoring Skip Conditions"  
  https://www.onerobotics.com/posts/2019/refactoring-skip-conditions/
- OneRobotics, "Using Conventions to Improve Your Workflow"  
  https://www.onerobotics.com/posts/2013/using-conventions-to-improve-your-workflow/
- OneRobotics, "Programming FANUC Robots with Variables and Constants"  
  https://www.onerobotics.com/posts/2021/programming-fanuc-robots-with-variables-and-constants/
- OneRobotics, "Introduction to KAREL Programming"  
  https://www.onerobotics.com/posts/2013/introduction-to-karel-programming/
- OneRobotics, "How to RUN FANUC Programs Concurrently with the RUN statement"  
  https://www.onerobotics.com/posts/2019/how-to-run-fanuc-programs-concurrently-with-the-run-statement/
- OneRobotics projects page  
  https://www.onerobotics.com/projects/
- `onerobotics/fexcel`  
  https://github.com/onerobotics/fexcel
- `onerobotics/tp_plus`  
  https://github.com/onerobotics/tp_plus
- `onerobotics/KUnit`  
  https://github.com/onerobotics/KUnit
- `onerobotics/go-fanuc`  
  https://github.com/onerobotics/go-fanuc

## Recommended Practices Observed

### 1. Keep TP Programs Short And Focused

OneRobotics emphasizes pendant readability: the TP editor shows few lines, so
large routines are hard to troubleshoot at the robot. The stated preference is
roughly under 60 lines where practical, with routines above about 100 lines as
good refactoring candidates.

Current project comparison:

- Strong match with the user's preference that `A_MAIN` should read like a flow
  chart.
- Our first migrated `A_MAIN` was too long and too close to the source
  `F_MAIN`; the greenfield `A_MAIN_G` direction is more aligned.
- Future generated main programs should be coordinators, not procedural dumps.

Project rule candidate:

- Main programs should be compact phase coordinators. Long guard logic,
  waits, IO operations, and motion details should be extracted unless keeping
  them inline makes a state transition clearer.

### 2. Extract Conditionals Into Subroutines

OneRobotics recommends moving condition-heavy approach/routing logic into
focused routines so the caller remains readable.

Current project comparison:

- Strong match with the user's preference for encapsulation, even for two or
  three lines when it improves readability.
- Our state-machine discussion should not result in one large state monolith.
  States can call small routines that perform guarded actions.

Project rule candidate:

- Prefer named `CALL` routines for repeated or nontrivial condition blocks.
  Keep the caller's transition intent visible.

### 3. Balance Indirection Against Duplication

OneRobotics favors reducing duplication, but acknowledges that indirection has
a readability cost.

Current project comparison:

- This matches our tension between generated defensive code and pendant
  readability.
- We should not hide everything behind generic helpers if the technician loses
  the cell story.

Project rule candidate:

- Use indirection for stable cell concepts: gripper actions, waits, handshakes,
  status checks, comment writing, and reusable searches. Avoid generic helpers
  whose call sites do not explain the robot action.

### 4. Use Subroutines For Operating IO

OneRobotics specifically recommends subroutines for IO operations such as
opening/closing a gripper, so an IO mapping change is made in one place.

Current project comparison:

- Strong match with our Robot Server comment map and SNPX allowlist thinking:
  IO should be named, mapped, and centralized.
- For generated TP, direct IO writes in high-level workflow code should be rare
  unless they are the state transition itself, such as an explicit handshake
  acknowledge.

Project rule candidate:

- Encapsulate device IO actions in named routines. Allow direct IO writes in a
  coordinator only when the write is itself the visible transition action.

### 5. Write Useful Error Messages

OneRobotics pushes error messages that explain the issue, likely causes, and
recovery path instead of vague alarms.

Current project comparison:

- Strong match with our user alarm/message discussions.
- We should not over-comment normal code, but alarms and fault exits should be
  operationally useful.

Project rule candidate:

- Generated user alarms should say what condition failed, what signals/values
  were expected, and what the operator should inspect next.

### 6. Minimize Arbitrary `JMP`/`LBL` Flow

OneRobotics warns against excessive jumping and recommends using labels/jumps
mostly for TP's missing control structures, guards, and localized recovery.

Current project comparison:

- Strong match with the user's complaint that diagrams lacking clear
  transitions were not real state machines.
- Our generated TP should not recreate opaque label spaghetti. If labels exist,
  they should map to a clear control structure, timeout branch, fault branch, or
  state transition.

Project rule candidate:

- Every generated label must have a purpose category: loop, branch, timeout,
  fault, select case, or end. No unlabeled "magic" jump targets.

### 7. Prefer `END` Over Jumping To End Labels

OneRobotics recommends using `END` when the intent is to end the routine,
instead of jumping to `LBL[999]` or similar. The reason is that an end label can
stop being the real end after later edits.

Current project comparison:

- Partial mismatch with our inherited `F_MAIN`/migration style, where `LBL[999]`
  is common.
- For generated `A_` programs, use `END` for simple subroutine termination. Use
  explicit fault/finish labels only when the code after the label performs real
  cleanup or state writes.

Project rule candidate:

- Do not jump to an end label merely to end. Use `END`. Reserve end/fault labels
  for meaningful shared cleanup.

### 8. Isolate Wait Statements

OneRobotics recommends putting waits with timeout handling into small routines
to keep main logic readable and keep timeout recovery close to the wait.

Current project comparison:

- Strong match with our global `$WAITTMOUT` policy, but our first generated
  drafts still kept too much wait/error detail in `A_MAIN`.
- A cleaner pattern is `CALL A_WAIT_SYNC1`, inspect return code, then transition.

Project rule candidate:

- For external waits, prefer `A_WAIT_*` routines returning status. The caller
  should show the transition; the wait routine should own timeout details.

### 9. Use `0` For Success / Normal Return Status

OneRobotics explicitly notes that FANUC tends to use `0` for successful or
normal return status, with nonzero indicating abnormal/error status, similar to
C convention.

Current project comparison:

- This directly supports switching away from our earlier HTTP-style TP return
  codes.
- HTTP-inspired labels may still be useful for documentation or PC-side APIs,
  but pendant-facing TP/KAREL should use `0 = OK`.

Project rule candidate:

```text
0   OK
1   NO_WORK
10  ACCEPTED
20  RUNNING
30  HELD
40  BUSY
50  GUARD_FAILED
60  TIMEOUT
70  NOT_FOUND
80  BAD_ARG
90  UNAVAILABLE
100 FAILED
999 UNKNOWN
```

### 10. Pass Return Registers As Parameters

In the skip-condition refactor, OneRobotics moves away from a hard-coded
status register and passes a return register index as a parameter, writing to
`R[AR[1]]`.

Current project comparison:

- Strong match with `TSKSTATUS('TASK_NAME', base_register, show_message)`.
- We should generalize this for reusable generated helpers rather than hard-code
  `R[80]`, `R[91]`, etc. inside utility routines.

Project rule candidate:

- Reusable TP/KAREL helpers should accept the destination status register when
  practical. Application phase programs may use a project-standard status
  register by contract.

### 11. Use Conventions To Avoid Re-Deciding Common Things

OneRobotics promotes convention over configuration for common registers,
position registers, labels, and product-case label ranges.

Current project comparison:

- Strong match with our project packs, cell maps, comment maps, and resource
  policies.
- We should maintain a project-local convention layer, not one universal global
  robot convention.

Project rule candidate:

- Each project pack should define conventional scratch/status registers,
  position ranges, IO ownership, alarm ranges, and generated program prefixes.

### 12. Prefer Explicit `SELECT` Cases Over Computed Jump Targets

OneRobotics prefers readable `SELECT` cases with an `ELSE` fault branch over
computed jumps because valid cases and error handling are visible.

Current project comparison:

- Strong match with human-reviewable generated TP.
- Also relevant to state machines: explicit transition cases are more
  reviewable than indirect state-to-label jumps.

Project rule candidate:

- Generated TP should prefer explicit `SELECT`/guard sequences over computed
  label jumps unless a generator can emit a reviewable transition table.

### 13. Use Named Variables/Constants But Keep Generated TP Close To Runtime TP

OneRobotics' TP+ introduced higher-level TP abstractions, but the later
fexcel article says the TP+ source could be too far removed from the compiled TP
that actually ran on the robot. The fexcel approach keeps standard TP line shape
while replacing names/constants from a spreadsheet.

Current project comparison:

- This is highly relevant to AI generation. We need source that is easier to
  author, but not so abstract that pendant/debug review becomes a translation
  exercise.
- Our structured specs are useful, but the review artifact must remain close to
  the generated `.LS`.

Project rule candidate:

- Use specs/tables for generation and validation, but produce `.LS` that is
  readable as normal TP. Avoid a custom high-level language unless it can
  round-trip into reviewable TP with clear traceability.

### 14. Keep Robot Data In A Reviewable External Map

fexcel manages FANUC robot data/comments through Excel, can create/diff/set
comments, and supports registers, PRs, IO, frames, constants, and user alarms.

Current project comparison:

- Strong match with our Robot Server comment reader/writer plan and the user's
  desire for human-reviewable lists.
- We should continue using explicit maps/plans for comments and alarms before
  writes.

Project rule candidate:

- Robot metadata writes must be generated from human-reviewable maps and
  verified by readback. Do not bury comment/alarm text only in procedural code.

### 15. Use KAREL For What TP Cannot Do, But Recognize Its Black-Box Cost

OneRobotics describes KAREL as compiled `.KL` to `.PC`; once loaded, the source
is not visible/step-through like TP. KAREL is powerful, but it changes the
debugging model.

Current project comparison:

- Strong match with our skepticism about using KAREL for everything.
- `TSKSTATUS` as a narrow reusable KAREL helper fits this model. Full workflow
  logic in KAREL would be harder to review on the pendant.

Project rule candidate:

- Keep motion/workflow TP-visible unless KAREL is clearly justified. Use KAREL
  for narrow capabilities TP cannot provide cleanly.

### 16. Treat `RUN` As True Concurrency

OneRobotics emphasizes that `RUN` starts concurrent execution and that the main
task proceeds immediately. It also highlights monitoring concurrent tasks from
the pendant.

Current project comparison:

- Strong match with our `TSKSTATUS` work and the user's identified race around
  handshakes.
- Generated programs must make task ownership explicit before `RUN`.

Project rule candidate:

- Every generated `RUN` requires ownership policy: pre-run status check,
  expected inactive states, post-run confirmation if needed, separate status
  registers per concurrent task, and defined cleanup/fault behavior.

### 17. Test KAREL And Tooling

KUnit provides a KAREL unit-test framework with assertions and browser output.
OneRobotics also has parser/runtime/data tools with tests in their repositories.

Current project comparison:

- Strong match with our local validator, round-trip, and tool-test philosophy.
- If KAREL grows beyond `TSKSTATUS`, we need a KAREL-specific test story rather
  than treating `.PC` as untestable.

Project rule candidate:

- Reusable KAREL helpers need compile evidence and a minimal test harness or
  equivalent live/offline proof before they become standard dependencies.

### 18. Robot Server / HTTP Metadata Access Is A First-Class Tooling Path

`go-fanuc` and `fexcel` both reflect a pattern of using robot HTTP/Robot Server
style access for robot data, comments, registers, PRs, frames, IO, alarms, and
program information.

Current project comparison:

- Strong match with our Robot Server metadata writer direction.
- For runtime values, our current conclusion still stands: SNPX remains better
  for typed, allowlisted, batchable value read/write. Robot Server is excellent
  for metadata.

Project rule candidate:

- Use Robot Server for comments/alarms/metadata where it is directly exposed
  and verifiable. Use SNPX or another typed runtime interface for live values.

## Direct Impact On Our Current Decisions

| Topic | Current Discussion | OneRobotics Pressure | Recommended Adjustment |
| --- | --- | --- | --- |
| Return codes | We debated HTTP-style `200/404/500` vs zero-success. | Explicitly supports `0` normal/success and nonzero abnormal. | Switch generated TP/KAREL return-code convention to `0 = OK`. |
| Main program shape | User says `A_MAIN` does not invite reading. | Main should be short/focused; waits and conditionals extracted. | Make `A_MAIN` a compact phase/state coordinator. |
| State machines | We are comparing procedural workflow vs explicit transitions. | Avoid jump spaghetti; make flow explicit. | Use explicit state/transition tables for orchestration, not giant label webs. |
| Waits/timeouts | We write `$WAITTMOUT` before use. | Isolate waits into small routines. | Use `A_WAIT_*` routines returning status for external waits. |
| Comments/alarms | User wants useful pendant review, not clutter. | Error messages should aid troubleshooting/recovery. | Focus comments before calls/transitions; make alarms operationally specific. |
| IO writes | We allowlist IO and discuss comments/Robot Server. | Use subroutines for operating IO. | Encapsulate device actions; direct writes only for visible handshakes/transitions. |
| KAREL | We have narrow `TSKSTATUS`; user is skeptical of all-KAREL. | KAREL is powerful but source is black-box on controller. | Keep KAREL narrow and utility-like. |
| Metadata | We planned Robot Server maps and human review lists. | fexcel/go-fanuc reinforce mapped metadata tooling. | Continue human-reviewable maps plus readback verification. |
| Abstraction | We use specs/generators. | TP+ shows productivity but source-distance risk; fexcel keeps TP line shape. | Keep generated `.LS` close to pendant-visible TP with traceable specs. |

## Proposed Project Rules To Carry Forward

1. Use zero-success status codes for pendant-facing TP/KAREL.
2. Keep main programs as compact coordinators.
3. Use explicit transition tables for generated workflow orchestration.
4. Extract external waits into small routines returning status.
5. Encapsulate device IO operations in named routines.
6. Use direct IO writes in coordinators only for visible handshakes or state
   transition actions.
7. Use `END` instead of jump-to-end labels unless shared cleanup is real.
8. Keep every generated label categorized and reviewable.
9. Pass destination status registers into reusable helpers when practical.
10. Keep KAREL narrow unless TP cannot reasonably express the behavior.
11. Keep robot metadata in human-reviewable maps and verify writes by readback.
12. Prefer source/generation approaches that preserve readable, normal-looking
    `.LS` as the primary robot review artifact.
