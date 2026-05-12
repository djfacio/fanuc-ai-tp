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

The existing `tools\Set-FanucSimulationEvidence.ps1` records the current status. `tools\New-FanucRoboguideEvidencePacket.ps1` generates a structured evidence packet and optional Markdown checklist from a program spec.

## Gate Policy

- No-motion diagnostics may use `not-required`.
- IO checks can be `not-required` only when manually reviewed and explicitly approved.
- Motion programs require `passed` simulation evidence before upload.
- Simulation evidence does not replace T1/manual physical verification.

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

Evidence classes:

- `no-motion`: RoboGuide optional, manual T1 required, no before/after snapshot required.
- `io-sequence`: RoboGuide and manual T1 required, before/after snapshot required.
- `motion`: RoboGuide and manual T1 required, before/after snapshot required.
