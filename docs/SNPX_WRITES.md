# SNPX Writes

SNPX is a read/write interface for this project. The status snapshot path stays read-only, but writes are planned as a separate allowlisted command path.

## Local Files

```text
config\snpx-writes.psd1
tools\Test-FanucSnpxWriteConfig.ps1
tools\New-FanucSnpxWritePlan.ps1
tools\Invoke-FanucSnpxLiveWrite.ps1
tools\Get-FanucSnpxCommissioningMatrix.ps1
```

The write allowlist is intentionally tied back to:

```text
config\cell-map.psd1
config\snpx-readonly.psd1
```

That means an SNPX write must be approved in the same cell resource map used by generated TP programs, and it must have a matching ASG projection entry.

Use the commissioning matrix to review the combined read/write map, projection ranges, collision rules, live-proof status, and restoration requirements:

```powershell
.\tools\Get-FanucSnpxCommissioningMatrix.ps1 -WriteMarkdown
```

## Current Scope

Approved planning entries:

- `R[90]`
- `R[91]`
- `R[97]`
- `R[98]`
- `R[99]`
- `DO[1]`

For this local commissioning/test project only, the broader scratch write boundary is `R[90]` through `R[99]` and `DO[1]` through `DO[80]`. A target still needs an explicit SNPX `AllowedWrites` entry and ASG mapping before the live SNPX write tool can use it. Establish a separate write policy per project/workcell. Production/status values outside this test policy, including `R[103]`, `R[107]`, `R[110]`, and outputs above `DO[80]`, are read-only unless separately approved.

The marker registers use integer ASG projection writes. `DO[1]` is an output write; plans that request `DO[1]=ON` require a matching restoration write back to `OFF` and post-restore readback evidence.

Dynamic scratch writes use `DynamicProjection` in `config\snpx-writes.psd1`. The live write tool adds one temporary `SETASG` row for the reviewed target into `%R00079` for that connection, writes through it, verifies readback, and restores outputs when required. This avoids adding every scratch output/register to the read snapshot map.

## Commands

Validate the write config:

```powershell
.\tools\Test-FanucSnpxWriteConfig.ps1
```

Create a write plan for a marker register:

```powershell
.\tools\New-FanucSnpxWritePlan.ps1 -Fanuc "R[99]" -Value 123
```

Create a write plan for the reviewed output:

```powershell
.\tools\New-FanucSnpxWritePlan.ps1 -Fanuc "DO[1]" -State ON
```

Create a dynamic write plan for a reviewed scratch target in this local test policy:

```powershell
.\tools\New-FanucSnpxWritePlan.ps1 -Fanuc "R[95]" -Value 9501
.\tools\New-FanucSnpxWritePlan.ps1 -Fanuc "DO[2]" -State ON
```

These commands do not write to the robot. They generate a JSON execution plan with the FANUC item, SNPX projection address, encoded word value, and live execution gates.

Approved plans also include exact operator approval text. A live execution must supply that phrase with `-ApprovalPhrase` so the command line records the reviewed target, value, and SNPX projection:

```powershell
.\tools\New-FanucSnpxWritePlan.ps1 -Fanuc "DO[1]" -State ON -Approved
```

## Live Write Gate

Before a live SNPX write tool is allowed:

1. Use the local `vendor\snpx-codec` source.
2. Connect to `192.168.5.10:60008`.
3. Program private ASG mapping from `config\snpx-readonly.psd1`.
4. Verify `$SNPX_ASG` by readback.
5. Read the current target value before writing.
6. Write only an allowlisted target from `config\snpx-writes.psd1`.
7. Read the target value after writing.
8. For output writes that require restoration, write the restore value and read it back.
9. Emit evidence that distinguishes ASG setup, pre-read, write, post-read, restore, and post-restore.

Dry-run live evidence:

```powershell
.\tools\Invoke-FanucSnpxLiveWrite.ps1 -PlanPath .\generated\cell-status\snpx-write-plan.json
```

Live execution requires the approved plan, the exact approval phrase, and `-AcceptLiveWrite`. If the plan requires restoration, it also requires `-RestoreAfterWrite`:

```powershell
.\tools\Invoke-FanucSnpxLiveWrite.ps1 `
  -PlanPath .\generated\cell-status\snpx-write-plan.json `
  -Execute `
  -AcceptLiveWrite `
  -RestoreAfterWrite `
  -ApprovalPhrase "I approve live SNPX write: DO[1]=ON via %R00015"
```

No SNPX write tool should modify system variables, UOP/SOP, DCS, motion state, production program state, or unmapped resources.

## Low-Level Codec Wrapper

The local codec wrapper exists for commissioning:

```powershell
.\tools\Invoke-FanucSnpxCodecTool.ps1 -Operation write-r -Start 5 -Value 123 -AcceptLiveWrite
```

Use it only after generating a matching write plan. The wrapper is deliberately low-level; the project safety policy lives in `config\snpx-writes.psd1` and the planning tools.
