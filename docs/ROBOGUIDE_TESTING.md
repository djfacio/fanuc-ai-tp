# RoboGuide Testing

RoboGuide is an optional high-fidelity test bench for generated TP programs.

## Current Evidence Command

Record manual simulation evidence:

```powershell
.\tools\Set-FanucSimulationEvidence.ps1 -ProgramName AI_HELLO -Status not-required -Notes "No-motion register/message workflow."
```

Record motion simulation or manual review evidence:

```powershell
.\tools\Set-FanucSimulationEvidence.ps1 `
    -ProgramName AI_MOTION_PR_READY `
    -Status passed `
    -MotionInvolved $true `
    -WorkcellPath "<reviewed RoboGuide workcell>" `
    -EvidencePacketPath .\generated\jobs\AI_MOTION_PR_READY\roboguide-evidence-packet.json `
    -Reviewer "<name>" `
    -Notes "<what was observed>"
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
- For motion, the operator is responsible for PR information, UFRAME, UTOOL, payload, path safety, and controller setup.

## Motion Programs

Motion programs may record RoboGuide or manual review evidence. The operator owns PR, frame, tool, payload, controller setup, and physical path correctness.
