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
- T1/manual pendant verification plan.
- Before/after status snapshot plan.
- Acceptance criteria.

8. Generate From Reviewed Template

Only after `Test-FanucMotionApplicationSpec.ps1` reports `ReadyForGeneration=True` should a motion template emit TP source. Early motion templates should be deterministic and reviewed-template-only.

9. Existing TP Gates Still Apply

After generation, use the existing local workflow gates:

```powershell
.\tools\Test-FanucLsSafety.ps1 -LsPath .\generated\sources\AI_APP.LS
.\tools\Invoke-FanucTpBuild.ps1 -LsPath .\generated\sources\AI_APP.LS -Force
.\tools\Invoke-FanucTpRoundTrip.ps1 -LsPath .\generated\sources\AI_APP.LS -Force
.\tools\Update-FanucJobManifest.ps1 -ProgramName AI_APP
.\tools\Get-FanucReviewPacket.ps1 -ProgramName AI_APP
```

10. Simulation, Upload, T1

Do not upload until local evidence and human review are complete. Do not run from PC tooling. Verify first in RoboGuide, then on the pendant in T1/manual mode.

## Phase 2 Starting Boundary

Phase 2 may define motion application specs and readiness checks. It does not yet generate motion TP. Motion generation starts only after a reviewed motion template exists and the validator reports the application spec as generation-ready.
