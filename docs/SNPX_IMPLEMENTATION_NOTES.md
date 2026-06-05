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

## User Alarm Severity Proof

On 2026-05-20, the controller accepted a private ASG projection for
`$UALRM_SEV[20]`:

```text
SETASG 79 2 $UALRM_SEV[20] 1
```

Readback before the proof returned `%R00079..%R00080 = [6,0]`, matching Robot
Server `UALM[20]` severity `6` (`STOP.L`). A user-approved SNPX write set the
projected value to `0`; SNPX readback returned `[0,0]`, and Robot Server
confirmed `UALM[20]` severity `0` (`WARN`).

Evidence:

```text
generated\metadata\snpx-ualm20-severity-proof.json
```

Local manual verification:

- `MARXUSVAR06181E REV A`, page 52: `$UALRM_SEV[i]` is BYTE RW, corresponds to
  user alarm `i`, and maps severities as `0 WARN`, `6 STOP.L`, `38 STOP.G`,
  `11 ABORT.L`, and `43 ABORT.G`. Initial severity is `6 STOP.L`.
- `B-83054EN/04`, page 46: Robot Integration Setup exposes User Alarm Severity
  choices `WARN`, `STOP.L`, `ABORT.L`, `STOP.G`, and `ABORT.G`.

This proves SNPX can read and write User Alarm severity through `$SNPX_ASG` on
this controller. It does not make alarm severity part of the generic SNPX
scratch-write lane; severity remains protected control-behavior configuration.
Use the named `asg-read-ualm-severity` / `asg-write-ualm-severity` tool path
instead of generic integer writes. That path accepts only manual-confirmed
values and rejects nonzero upper byte/word readback.

Later in the same session, the robot owner manually changed `UALM[20]` severity
to `43` (`ABORT.G`) while message-write testing was in progress. That value is
operator-side evidence, not proof of a message-write side effect.

## User Alarm Message Proof

Local manual evidence confirms that `UALM[i]` displays text stored in
`$UALRM_MSG[i]`. On 2026-05-20, the controller accepted this private ASG
projection:

```text
SETASG 79 30 $UALRM_MSG[20] 1
```

Readback of populated `UALM[4]` text showed the string layout used by this
controller: two ASCII characters per `%R` word, low byte first. For example,
`RECIPE NOT READY` read as:

```text
[17746,18755,17744,20000,21583,21024,16709,22852,...]
```

A user-approved SNPX write set `UALM[20]` message text to `SNPX MSG TEST`.
SNPX readback returned:

```text
[20051,22608,19744,18259,21536,21317,84,0,...]
```

Robot Server independently confirmed the message as `SNPX MSG TEST`.

Evidence:

```text
generated\metadata\snpx-ualm20-message-proof.json
```

This proves SNPX can project and write `$UALRM_MSG[20]` as packed text on this
controller. Keep Robot Server as the preferred alarm metadata writer anyway:
Robot Server exposes alarm message and severity as separate operator-facing
fields, while SNPX string writes need stricter length and encoding guards before
they are allowed into a production writer.

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

1. Connect to the configured controller host, for example `192.168.0.10:60008`.
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
.\tools\Invoke-FanucSnpxCodecTool.ps1 -Operation asg-read-ualm-severity -SetupFile .\generated\metadata\snpx-ualm20-severity-asg.txt -Start 79
```

It also has low-level write operations, but those require `-AcceptLiveWrite` and should be used only after creating a reviewed plan with `New-FanucSnpxWritePlan.ps1`.

For alarm severity, do not use `asg-write-r` except during low-level proof work.
Use the severity-specific operation so manual-confirmed enum validation and
upper-word guards run before and after the write:

```powershell
.\tools\Invoke-FanucSnpxCodecTool.ps1 -Operation asg-write-ualm-severity -SetupFile .\generated\metadata\snpx-ualm20-severity-asg.txt -Start 79 -Severity ABORT.G -AcceptLiveWrite
```

The higher-level live read wrapper consumes `config\snpx-readonly.psd1` and emits the exact `CLRASG` / `SETASG` sequence:

```powershell
.\tools\Invoke-FanucSnpxLiveRead.ps1
.\tools\Invoke-FanucSnpxLiveRead.ps1 -Execute -AcceptAsgSetup
```
