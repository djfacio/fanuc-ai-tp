# SNPX Writes

SNPX is a read/write interface for this project. The status snapshot path stays read-only, but writes are planned as a separate allowlisted command path.

## Local Files

```text
config\snpx-writes.psd1
tools\Test-FanucSnpxWriteConfig.ps1
tools\New-FanucSnpxWritePlan.ps1
```

The write allowlist is intentionally tied back to:

```text
config\cell-map.psd1
config\snpx-readonly.psd1
```

That means an SNPX write must be approved in the same cell resource map used by generated TP programs, and it must have a matching ASG projection entry.

## Current Scope

Approved planning entries:

- `R[90]`
- `R[91]`
- `R[97]`
- `R[98]`
- `R[99]`
- `DO[1]`

The marker registers are ready for the first live write implementation once the private ASG handshake is wired. `DO[1]` remains marked `RequiresLiveProof` because the planned path writes through the ASG `%R` projection, and we need a controlled live proof before treating that IO write as commissioned.

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

These commands do not write to the robot. They generate a JSON execution plan with the FANUC item, SNPX projection address, encoded word value, and live execution gates.

## Live Write Gate

Before a live SNPX write tool is allowed:

1. Use the local `vendor\snpx-codec` source.
2. Connect to `192.168.5.10:60008`.
3. Program private ASG mapping from `config\snpx-readonly.psd1`.
4. Verify `$SNPX_ASG` by readback.
5. Read the current target value before writing.
6. Write only an allowlisted target from `config\snpx-writes.psd1`.
7. Read the target value after writing.
8. Emit evidence that distinguishes ASG setup, pre-read, write, and post-read.

No SNPX write tool should modify system variables, UOP/SOP, DCS, motion state, production program state, or unmapped resources.

## Low-Level Codec Wrapper

The local codec wrapper exists for commissioning:

```powershell
.\tools\Invoke-FanucSnpxCodecTool.ps1 -Operation write-r -Start 5 -Value 123 -AcceptLiveWrite
```

Use it only after generating a matching write plan. The wrapper is deliberately low-level; the project safety policy lives in `config\snpx-writes.psd1` and the planning tools.
