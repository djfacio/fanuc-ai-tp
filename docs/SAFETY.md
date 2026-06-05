# Safety Policy

This project produces robot programs. Default behavior must be conservative, observable, and reversible.

The standards-driven review posture and reusable generation rules live in
`docs/STANDARDS_RULES.md`. Use that file when deciding whether a project-specific
exception is justified.

## Default Rules

- New generated program names must start with the configured prefix, currently `A_`. Legacy `AI_` programs are still recognized for existing artifacts and robot cleanup analysis.
- The `.LS` filename and `/PROG` header must match exactly.
- Uploading a program must not run it.
- Do not overwrite production programs.
- Keep physical run decisions operator-owned and outside the code-generation gates.
- Do not require repeated pendant-review approval for upload when local evidence
  passes under the active project commissioning policy.
- Motion generation requires explicit frame, tool, point, speed, zone, payload, reach, collision, and verification assumptions.

## Blocked Unless Explicitly Reviewed

- DCS changes or DCS references.
- System variable writes.
- UOP behavior.
- `RUN`, `ABORT`, or background task control.
- KAREL program generation or deployment.
- Controller-side socket services.
- SNPX writes.
- Calls into production programs.
- Anything that changes mastering, frames, payloads, safety, or controller configuration.

The active static LS blocked-pattern policy lives in:

```text
config/safety-rules.psd1
```

Update that file when adding reviewed safety rules, then run:

```powershell
.\tools\Invoke-FanucToolTests.ps1
```

## Required Evidence For Motion

- Program intent and expected robot behavior.
- Tool and user frame selections.
- Payload assumptions.
- Position source and coordinate convention.
- Speed, termination, and zone assumptions.
- RoboGuide or equivalent simulation notes.
- Operator-owned physical verification notes, when the operator chooses to record them.
- Recovery and abort expectations.

## Operator-Owned Commissioning Boundary

AI may help draft specs, generate candidate code, explain controller behavior,
or compare artifacts. In this project, the experienced robot programmer owns
pendant selection, low-speed step testing, deadman control, robot-side setup,
and final execution judgment.

The tooling should not convert that operator-owned commissioning practice into
repeated upload prompts. It should enforce local evidence, resource policies,
and explicit policy decisions when authority expands.
