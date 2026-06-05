# Source Authority

This project uses FANUC sources, local cell evidence, and operator experience
to generate robot-facing code. Not every useful source has the same authority.
Use this policy when turning a source into a rule, template, or generated TP
behavior.

## Authority Levels

### A0: Cell-Specific Project Policy

Examples:

- Approved frames, tools, payload schedules, PR ranges, register ranges, IO
  ownership, alarms, and startup/recovery assumptions.
- Operator-owned setup decisions for a specific workcell.
- Project cell maps, commissioning policy, and reviewed resource lists.

Use:

- Required before generated code touches project resources.
- Overrides generic templates only inside the documented project scope.
- Must record owner, date, reason, and scope when it intentionally differs from
  a generic rule.

### A1: FANUC Manuals And Engineering Bulletins

Examples:

- Local trusted PDF manuals in `C:\Dev\Fanuc Robot Manuals`.
- FANUC MyPortal eDocs Manuals and Engineering Bulletins metadata.
- Downloaded manuals/bulletins only when the user explicitly approves storing
  them in the separate manuals project, not this public repo.

Use:

- Primary authority for controller behavior, TP/KAREL syntax, system variables,
  program attributes, group masks, motion behavior, IO/comment mechanisms,
  Robot Server/SNPX/PCDK behavior, and safety-related controller features.
- Cite manual ID/title and page/section when a rule depends on a manual.
- Engineering Bulletins can justify version- or option-specific exceptions, but
  the affected controller/software scope must be recorded.

### A2: Local Robot Evidence

Examples:

- MakeTP/PrintTP round-trip evidence.
- Robot FTP upload/readback hash and decode evidence.
- Read-only Robot Server/SNPX/PCDK snapshots.
- Pendant observations reported by the responsible operator.

Use:

- Confirms what this controller/workcell actually does.
- Can expose a gap between a generic rule and the installed option set.
- Does not by itself create a reusable rule for other projects.
- For migration work, read-only controller metadata can outrank stale legacy
  comments or branch names inside the same project when both are reviewed and
  the discrepancy is recorded in the generated spec/design notes.

### A3: FANUC Training, Tech Transfer, FAQ, And ASI Material

Examples:

- MyPortal Tech Transfer Shorts.
- FANUC Friday Webinars.
- ASI Events and Engineering Tech Transfer pages.
- Technical Support FAQ.
- FANUC Academy training catalog.
- CRX application videos.

Use:

- Strong source of practice, vocabulary, application patterns, and things to
  investigate.
- Good basis for review prompts, checklist items, template ideas, and
  discussion questions.
- Not sufficient by itself to justify robot-facing behavior that depends on
  controller semantics. Verify against A1 manuals/bulletins or mark the rule as
  training-derived.

### A4: Community And External Practice Sources

Examples:

- OneRobotics articles and GitHub examples.
- Robot-Forum threads with experienced practitioner answers.
- Vendor examples, forum posts, application notes outside FANUC authority.

Use:

- Useful for comparative practice and code style review.
- Robot-Forum is treated as a somewhat trusted practitioner source when answers
  from experienced users converge or match FANUC/manual/local evidence.
- Treat as advisory unless confirmed by A1/A2/A0.
- Never use external mirrors of FANUC manuals as authority when local or
  MyPortal sources are available.

## Rule Adoption

When adding a generation rule, classify it:

- `manual-confirmed`: backed by A1 with citation.
- `project-policy`: backed by A0.
- `controller-evidence`: backed by A2.
- `training-derived`: inspired by A3 and pending A1/A2 confirmation.
- `practice-advisory`: inspired by A4 and pending stronger authority.

Rules that affect generated TP/KAREL code must be either `manual-confirmed`,
`project-policy`, or `controller-evidence` before they become hard validators.
`training-derived` and `practice-advisory` rules may drive review prompts and
draft design, but must not silently become upload gates.

## MyPortal Resource Handling

MyPortal metadata indexes are local generated artifacts and should stay ignored
by git unless the user explicitly approves publishing them.

Current local metadata indexes:

- `generated\myportal-index\edocs-english-manuals-and-bulletins.json`
- `generated\myportal-index\edocs-shaped-index.json`
- `generated\myportal-index\MYPORTAL_RESOURCE_INDEX.md`
- `generated\myportal-index\MYPORTAL_VIDEO_RESOURCE_INDEX.md`

Do not include cookies, tokens, account fields, or download URLs in project
docs. Do not download MyPortal files without explicit approval and a destination
outside this public repo.

## Practical Use In Code Generation

Before generating or changing motion-capable `A_` programs:

1. Identify the project policy that grants frames, tools, payloads, PRs, IO,
   registers, alarms, and program call authority.
2. Identify the manuals/bulletins that confirm any controller behavior being
   relied on.
3. Use training/video/FAQ resources to improve vocabulary, application
   decomposition, and review questions.
4. Keep generated code reviewable on the pendant; do not hide a training-derived
   idea inside opaque generated code.
5. Record any unresolved source gap as a review item rather than assuming it is
   settled.

## Program Comprehension Evidence

General software-comprehension sources support the project's pendant-readable
control-flow policy: prefer a mostly linear normal path, use structured
selection/iteration concepts where TP permits, keep labels as visible control
landmarks, and avoid dense arbitrary jumps that force reviewers to reconstruct a
control-flow graph. This is supported by structured-programming practice,
program-comprehension research on spaghetti-code/cognitive-complexity effects,
and local pendant-review experience. It does not ban labels; TP labels remain
appropriate for loop starts, timeout/error exits, common cleanup, normal finish,
and reviewed retry/recheck points.

Useful background sources:

- Dijkstra, "Go To Statement Considered Harmful", Communications of the ACM,
  1968. Authority: practice-advisory for uncontrolled jump risk, not a TP label
  ban.
- Knuth, "Structured Programming with go to Statements", ACM Computing Surveys,
  1974. Authority: practice-advisory for the caveat that structured, purposeful
  jumps can be legitimate.
- SonarSource Cognitive Complexity. Authority: practice-advisory for the idea
  that breaks in linear flow, nesting, and jumps add understandability cost.

## Human Factors Evidence

Human cognitive limits are directly relevant to pendant-reviewed TP. Reviewers
do not simply read statements; they build and maintain a mental model of the
cell state, active resource ownership, intended next action, and possible fault
outcomes. Generated code should reduce unnecessary memory load so the reviewer
can spend attention on whether the robot behavior is correct.

Relevant evidence:

- Working memory is limited. Classic and modern working-memory research varies
  on the exact number, but the practical result is stable: do not force a
  reviewer to hold many flags, registers, label targets, task states, and
  pending side effects at once.
- Cognitive Load Theory distinguishes unavoidable task complexity from
  extraneous load introduced by presentation. TP code cannot remove the real
  complexity of the cell, but it can avoid adding avoidable complexity through
  opaque labels, stale comments, scattered decisions, and hidden state writes.
- Program-comprehension research shows programmers form mental models using
  control-flow, data-flow, goal, and domain information. Generated TP should
  expose all four: what runs next, what state changes, why the section exists,
  and what cell concept it represents.
- Program tracing research links working-memory load to mistakes in remembering
  program state. This supports breadcrumb registers, controller comments,
  explicit status contracts, and readable local state transitions.
- Task switching has a measurable cognitive cost. A TP reviewer who must jump
  across labels, child routines, undocumented resources, and separate review
  notes pays that cost repeatedly. Good decomposition should reduce switching by
  making each child routine a meaningful chunk.
- Usability research favors recognition over recall. Use controller comments,
  station-literate names, section remarks, and nearby wait/status contracts so
  the reviewer recognizes intent on the pendant instead of recalling it from a
  separate document.

Useful background sources:

- Sweller Cognitive Load Theory and later cognitive architecture summaries.
- Pennington and Letovsky program-comprehension work on mental models.
- Crichton, Agrawala, and Hanrahan, "The Role of Working Memory in Program
  Tracing", CHI 2021.
- Nielsen Norman Group usability heuristics, especially recognition rather than
  recall and visibility of system status.
- Task-switching psychology literature on switch cost.
