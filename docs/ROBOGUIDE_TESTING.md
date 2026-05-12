# RoboGuide Testing

RoboGuide is the high-fidelity test bench for generated TP programs.

## Current Evidence Command

Record manual simulation evidence:

```powershell
.\tools\Set-FanucSimulationEvidence.ps1 -ProgramName AI_HELLO -Status not-required -Notes "No-motion register/message workflow."
```

This writes:

```text
generated/jobs/<PROGRAM>/simulation.json
```

## Minimum Simulation Notes

- RoboGuide workcell path.
- Program under test.
- Whether motion is involved.
- Test mode and override.
- Inputs/outputs observed.
- Alarms or warnings.
- Expected vs actual behavior.
- Screenshots or logs, if available.

## Motion Programs

Motion programs require RoboGuide evidence unless explicitly waived by a human reviewer with a written reason.
