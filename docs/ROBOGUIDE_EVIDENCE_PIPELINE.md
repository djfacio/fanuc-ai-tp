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

The existing `tools\Set-FanucSimulationEvidence.ps1` records the current status. The next increment is a generated test-plan file that humans can execute in RoboGuide and then attach back to the manifest.

## Gate Policy

- No-motion diagnostics may use `not-required`.
- IO checks can be `not-required` only when manually reviewed and explicitly approved.
- Motion programs require `passed` simulation evidence before upload.
- Simulation evidence does not replace T1/manual physical verification.

## Next Tooling Target

Generate `generated\jobs\<PROGRAM>\roboguide-test-plan.md` from the spec and manifest. The plan should include setup, run steps, expected observations, and evidence fields.
