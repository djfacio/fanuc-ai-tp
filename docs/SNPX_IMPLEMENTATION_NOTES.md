# SNPX Implementation Notes

These are the project-owned notes for the FANUC SNPX path. They exist here so future work does not rely on another local checkout.

## Transport

- Production default port: TCP `60008`.
- Alternate endpoint sometimes seen in SNPX/SRTP clients: TCP `18245`.
- Use `60008` for this project unless the commissioning record says otherwise.
- The `60008` endpoint uses an initial 56-byte zero INIT followed by the FANUC structured hello handled by `vendor\snpx-codec`.

## Addressing

SNPX exposes GE-style PLC memory. The wire layer reads and writes areas like `%R`, `%I`, `%Q`, `%AI`, and `%AQ`.

FANUC robot data is projected into that address space. For numeric registers, position registers, system variables, alarms, and many typed items, the projection is controlled by `$SNPX_ASG`.

Project rules:

- Use SNPX V2 private per-connection mapping.
- On every connect, program the mapping rather than trusting controller-global state.
- Use `CLRASG` before project-owned assignments.
- Use `SETASG` for each configured read.
- Read back `$SNPX_ASG` before trusting values.
- Treat unassigned `%R == 0` as a failure mode, not a valid default.
- Stay within the 80-slot ASG budget.

## Address Math

- Word selectors use `target_index = address - 1`.
- Bit selectors use a bit-level `target_index = address - 1`.
- Byte selectors use `target_index = address - 1`.

This matters for IO: do not collapse bit-selector reads to byte indexes in project code. The local codec centralizes this in `vendor\snpx-codec\src\addr.rs`.

## Read-Only Status Plan

The current read-only plan lives in:

```text
config\snpx-readonly.psd1
```

It projects selected registers and output states into `%R00001` through `%R00028` through system probes plus ASG slots 1 through 12. These are not direct native FANUC addresses; they are the project-owned GE memory projection to be programmed per connection.

## Live Reader Acceptance

A live SNPX reader is not done until it can:

1. Connect to `192.168.5.10:60008`.
2. Complete the SNPX init handshake.
3. Probe `$SNPX_PARAM.$VERSION` and confirm V2 behavior.
4. Probe `$SNPX_PARAM.$NUM_CIMP`.
5. Program the private ASG map from `config\snpx-readonly.psd1`.
6. Verify every configured ASG slot by readback.
7. Read the contiguous `%R` window for the status snapshot.
8. Emit `generated\cell-status\snpx-values.json`.
9. Produce failure output that clearly distinguishes connection failure, ASG verification failure, and read failure.

Until those gates exist, `Invoke-FanucSnpxReadSnapshot.ps1` remains plan-only.

## Local Codec CLI

The local Rust codec now includes a small CLI:

```powershell
.\tools\Invoke-FanucSnpxCodecTool.ps1 -Operation probe
.\tools\Invoke-FanucSnpxCodecTool.ps1 -Operation read-r -Start 1 -Count 9
```

It also has low-level write operations, but those require `-AcceptLiveWrite` and should be used only after creating a reviewed plan with `New-FanucSnpxWritePlan.ps1`.

The higher-level live read wrapper consumes `config\snpx-readonly.psd1` and emits the exact `CLRASG` / `SETASG` sequence:

```powershell
.\tools\Invoke-FanucSnpxLiveRead.ps1
.\tools\Invoke-FanucSnpxLiveRead.ps1 -Execute -AcceptAsgSetup
```
