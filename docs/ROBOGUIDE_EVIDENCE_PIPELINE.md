# RoboGuide Evidence Pipeline

RoboGuide evidence should become a first-class gate for programs that require motion, IO sequencing, or cell integration.

## Evidence Record

Each simulation run should record:

- Program name and artifact hashes.
- Workcell path and controller version.
- Robot backup or image baseline.
- Test mode and override.
- Frames, tools, payload assumptions, and fixture state.
- Expected observations.
- Actual observations.
- Pass/fail status and reviewer.

The existing `tools\Set-FanucSimulationEvidence.ps1` records optional evidence status. `tools\New-FanucRoboguideEvidencePacket.ps1` generates a structured evidence packet and optional Markdown notes from either a no-motion `program-spec.json` or a motion `motion-application-spec.json`.

## Gate Policy

- No-motion diagnostics may use `not-required`.
- IO checks can be `not-required` only when manually reviewed and explicitly approved.
- Motion programs require `passed` simulation evidence before upload.
- Simulation evidence is optional project evidence and does not replace operator-owned robot-side decisions.

## Next Tooling Target

Generate `generated\jobs\<PROGRAM>\roboguide-evidence-packet.json` and optional Markdown from the spec. The packet includes evidence class, required sections, expected writes, setup/run/snapshot steps, and result fields.

## Commands

Validate the evidence policy:

```powershell
.\tools\Test-FanucRoboguideEvidenceConfig.ps1
```

Generate an evidence packet from an example spec:

```powershell
.\tools\New-FanucRoboguideEvidencePacket.ps1 `
    -SpecPath .\examples\AI_IODIAG.program-spec.json `
    -WriteMarkdown `
    -Force
```

For the first PR-waypoint motion template:

```powershell
.\tools\New-FanucMotionLsFromSpec.ps1 `
    -SpecPath .\tests\fixtures\valid\AI_MOTION_PR_READY.motion-application.json `
    -Force

.\tools\New-FanucRoboguideEvidencePacket.ps1 `
    -SpecPath .\generated\jobs\AI_MOTION_PR_READY\motion-application-spec.json `
    -WriteMarkdown `
    -Force
```

The motion evidence packet records reviewed UFRAME, UTOOL, payload, each `J/L PR[n]` line, speed, termination, path review expectations, and before/after snapshot requirements.

Evidence classes:

- `no-motion`: optional RoboGuide/manual notes, no before/after snapshot required.
- `io-sequence`: optional RoboGuide/manual notes, before/after snapshots only when the project wants them.
- `motion`: optional RoboGuide/manual notes, with operator-owned robot setup and physical run decisions.
