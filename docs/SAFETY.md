# Safety Policy

This project produces robot programs. Default behavior must be conservative, observable, and reversible.

## Default Rules

- Generated program names must start with the configured prefix, currently `AI_`.
- The `.LS` filename and `/PROG` header must match exactly.
- Uploading a program must not run it.
- Do not overwrite production programs.
- Use T1/manual verification before production use.
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
- Manual pendant verification notes.
- Recovery and abort expectations.

## Human Review Boundary

AI may help draft specs, generate candidate code, explain controller behavior, or compare artifacts. A human with FANUC experience must review the safety contract and generated robot-facing code before upload or execution, especially for motion or controller integration.
