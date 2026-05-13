# Real Application TP Workflow

This workflow is for real FANUC TP applications, including motion. It is intentionally more demanding than the no-motion diagnostic workflow.

The key rule: motion generation begins only after the application has a reviewed motion application spec. The first motion templates should reference reviewed frames, tools, payloads, and taught points or reviewed position registers. Do not generate arbitrary Cartesian motion from natural language.

## Workflow

1. Intake

Capture the application purpose, workcell, robot, controller, payload, tooling, fixture context, operator location, and success criteria.

2. Project Policy

Create or review the project/workcell policy:

```powershell
.\tools\Test-FanucCellMap.ps1
.\tools\Invoke-FanucProjectHealthCheck.ps1 -WriteMarkdown
```

The local commissioning scratch policy does not carry over to another project.

3. Motion Application Spec

Create a motion application spec using:

```text
schemas\motion-application-spec.schema.json
examples\applications\AI_APP_PICK_PLACE.motion-application.json
```

Validate it:

```powershell
.\tools\Test-FanucMotionApplicationSpec.ps1 -SpecPath .\examples\applications\AI_APP_PICK_PLACE.motion-application.json
```

A planning spec can be valid without being ready for generation. `ReadyForGeneration=false` is expected until all gates are reviewed.

4. Resource Review

Before generation-ready status:

- UFRAME number, name, source, and verification must be explicit.
- UTOOL number, name, source, and verification must be explicit.
- Payload schedule and end-effector assumptions must be explicit.
- Points must be taught/reviewed or position-register based with touch-up requirements documented.
- IO, registers, and CALL targets must be in the project cell map.

5. Motion Design

The motion plan must define:

- Motion types, such as `J` and `L`.
- Speed policy.
- FINE/CNT termination policy.
- Approach and retract behavior.
- Clearance around fixtures, tools, and operators.
- Recovery plan.
- A line-level `motionSequence` with reviewed PR targets, speed, and termination for each move.

6. Safety Review

Generation is blocked until these are true:

- DCS/safety boundaries reviewed.
- Interlocks reviewed.
- Operator location reviewed.
- Fault handling reviewed.
- No controller configuration writes.
- Production overwrite disabled.

7. Evidence Plan

Every real motion application requires:

- RoboGuide evidence plan.
- Operator-owned physical verification plan.
- Before/after status snapshot plan.
- Acceptance criteria.

8. Generate From Reviewed Template

Only after `Test-FanucMotionApplicationSpec.ps1` reports `ReadyForGeneration=True` should a motion template emit TP source. Early motion templates should be deterministic and reviewed-template-only.

The first supported motion template is:

```text
pr-waypoint-sequence-v1
```

It emits:

- `UFRAME_NUM=<reviewed frame>`
- `UTOOL_NUM=<reviewed tool>`
- `PAYLOAD[<reviewed schedule>]`
- `J PR[n] ...` and `L PR[n] ...` moves from the reviewed `motionSequence`

It does not emit Cartesian position records, teach points, frame writes, tool writes, PR writes, DCS edits, system variable writes, `RUN`, or `ABORT`.

Generate offline LS from a reviewed generation-ready spec:

```powershell
.\tools\New-FanucMotionLsFromSpec.ps1 -SpecPath .\tests\fixtures\valid\AI_MOTION_PR_READY.motion-application.json -Force
```

For the local PR300-310 test range:

```powershell
.\tools\New-FanucMotionLsFromSpec.ps1 -SpecPath .\examples\applications\AI_PR300_PATH.motion-application.json -Force
.\tools\Invoke-FanucTpRoundTrip.ps1 -LsPath .\generated\sources\AI_PR300_PATH.LS -Force
```

Generate RoboGuide/manual evidence notes when useful:

```powershell
.\tools\New-FanucRoboguideEvidencePacket.ps1 -SpecPath .\generated\jobs\AI_MOTION_PR_READY\motion-application-spec.json -WriteMarkdown -Force
```

If RoboGuide/manual verification is useful, record optional simulation/manual evidence:

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

9. Existing TP Gates Still Apply

After generation, use the existing local workflow gates:

```powershell
.\tools\Test-FanucLsSafety.ps1 -LsPath .\generated\sources\AI_APP.LS
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_APP.LS -Force
.\tools\Invoke-FanucTpRoundTrip.ps1 -LsPath .\generated\sources\AI_APP.LS -Force
.\tools\Update-FanucJobManifest.ps1 -ProgramName AI_APP
.\tools\Get-FanucReviewPacket.ps1 -ProgramName AI_APP
```

10. Optional Evidence, Upload, Readback

Do not run from PC tooling. Operator-owned robot-side setup, PR correctness, frame/tool/payload setup, and physical path verification remain outside the tracked code-generation gates.

## Phase 2 Starting Boundary

Phase 2 now has three reviewed offline motion generator boundaries: `pr-waypoint-sequence-v1`, `approach-process-retract-v1`, and `io-motion-sequence-v1`. They are intentionally narrow and PR-based; IO is emitted only as reviewed allowlisted actions in the IO template. The tracked tool states are `planned`, `generationReady`, `generated`, `compiled`, `roundTripPassed`, `reviewed`, `uploaded`, and `readbackPassed`.
