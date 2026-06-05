# Project Metadata Workflow

Project metadata is controller-resident documentation and operator-facing
configuration that supports generated TP programs. Examples include register
comments, position-register comments, IO comments, and user alarm messages.

The workflow is intentionally list-first:

1. Codex proposes human-reviewable lists.
2. The robot owner reviews and confirms the lists.
3. Tooling generates a narrow writer only from confirmed rows.
4. The writer snapshots existing metadata, writes confirmed rows, then verifies
   readback.

Do not generate a metadata writer directly from conversational guesses. The
reviewable list is the contract.

## Reviewable Lists

Every proposed row must show:

| Field | Meaning |
| --- | --- |
| `family` | Resource family, such as `R`, `PR`, `DI`, `DO`, `RI`, `RO`, `GI`, `GO`, `UALM` |
| `index` | Resource number |
| `current` | Current controller value/comment when available |
| `proposed` | Proposed value/comment |
| `reason` | Why the new text belongs there |
| `source` | Program/spec/signal/state that caused the proposal |
| `status` | `proposed`, `approved`, `rejected`, or `defer` |

Only `approved` rows may be emitted into writer source.

## Preferred Interfaces

Use the built-in Robot Server as the first read-only metadata source when the
controller is reachable. It exposes comment and user-alarm pages through
`/KAREL/ComGet`, which lets tooling build review lists from actual controller
state without deploying KAREL or using PCDK.

Preferred order:

| Task | Preferred route |
| --- | --- |
| Snapshot current comments/user alarms | Robot Server `ComGet` |
| Build human-reviewable proposal list | Local deterministic tooling |
| Write approved comments | `New-FanucRobotServerCommentWritePlan.ps1` plus `Invoke-FanucRobotServerCommentWrite.ps1` |
| Write user alarm messages/severity | `New-FanucRobotServerAlarmWritePlan.ps1` plus `Invoke-FanucRobotServerAlarmWrite.ps1` |
| Runtime values and signal tests | SNPX |
| Fallback comment writer | KAREL narrow utility |

Do not use Robot Server `ComSet` directly. Use the generated plan/executor pair
so the exact target family, index, old value, new value, function code, URL, and
readback proof are captured.

## Comment Metadata Lane

This lane is for comments only. It must not write signal values, register
values, PR positions, frames, tools, payloads, IO assignments, IO modes, or
system variables.

Supported first-pass families:

| Family | KAREL API | Notes |
| --- | --- | --- |
| `R[n]` | `GET_REG_CMT`, `SET_REG_CMT` | Numeric register comments |
| `PR[n]` | `GET_PREG_CMT`, `SET_PREG_CMT` | Position-register comments only, not PR values |
| `SR[n]` | `GET_SREG_CMT`, `SET_SREG_CMT` | String register comments, optional |
| `DI[n]` | `GET_PORT_CMT`, `SET_PORT_CMT` with `IO_DIN` | Digital input comments |
| `DO[n]` | `GET_PORT_CMT`, `SET_PORT_CMT` with `IO_DOUT` | Digital output comments |
| `RI[n]` | `GET_PORT_CMT`, `SET_PORT_CMT` with `IO_RDI` | Robot input comments |
| `RO[n]` | `GET_PORT_CMT`, `SET_PORT_CMT` with `IO_RDO` | Robot output comments |
| `UI[n]` | `GET_PORT_CMT`, `SET_PORT_CMT` with `IO_UOPIN` | User operator panel input comments |
| `UO[n]` | `GET_PORT_CMT`, `SET_PORT_CMT` with `IO_UOPOUT` | User operator panel output comments |
| `GI[n]` | `GET_PORT_CMT`, `SET_PORT_CMT` with `IO_GPIN` | Group input comments |
| `GO[n]` | `GET_PORT_CMT`, `SET_PORT_CMT` with `IO_GPOUT` | Group output comments |
| `AI[n]` | `GET_PORT_CMT`, `SET_PORT_CMT` with analog IO type | Analog input comments |
| `AO[n]` | `GET_PORT_CMT`, `SET_PORT_CMT` with analog IO type | Analog output comments |
| `F[n]` | Robot Server `ComSet?sFc=19` | Flag comments |

The installed `KLIOTYPS.KL` also defines `IO_GPIN32` and `IO_GPOUT32`. Do not
use the 32-bit group IO constants unless the project list explicitly says the
target is the 32-bit group IO family.

Generated writer rules:

- Use `%NOLOCKGROUP`.
- Include only required environments: `REGOPE` for register/PR/SR comments and
  `IOSETUP` plus `KLIOTYPS` for port comments.
- Read existing comment before write.
- Write only approved rows.
- Read back after write and report mismatch.
- Keep one generated writer per project pack unless the approved list is large
  enough to justify subsystem splits.

For the current Robot Server route, the generated writer is a JSON plan plus a
PowerShell executor rather than KAREL source. It still follows the same rules:
comments only, approved rows only, old-comment check before execution, and
readback after every live write.

## User Alarm Metadata Lane

User alarm messages and severities are not comments. They are system/operator
behavior metadata and must use a stricter lane.

Confirmed local manual basis:

- `B-83284EN/12`, page 157: the User Alarm setup screen sets the displayed user
  alarm message.
- `B-83284EN/12`, page 284: `UALM[i]` displays the message from
  `$UALRM_MSG[i]`; `$UALRM_MSG` is saved to `SYSVARS.SV`.
- `B-83284EN/12`, page 993 and `MARXUSVAR06181E REV A`, page 52:
  `$UALRM_SEV[i]` is RW and maps user alarm severity.
- `B-83054EN/04`, page 46: Robot Integration Setup Tool exposes user alarm
  message text and severity choices.
- `B-83144EN-1/02`, pages 266 and 358-359: KAREL `GET_VAR` and `SET_VAR` can
  access `*SYSTEM*` variables, but FANUC warns that modifying system variables
  can cause unexpected results.

Known severity values:

| Value | Severity |
| ---: | --- |
| `0` | `WARN` |
| `6` | `STOP.L` |
| `38` | `STOP.G` |
| `11` | `ABORT.L` |
| `43` | `ABORT.G` |

Initial severity is `6` (`STOP.L`).

User alarm workflow:

1. Generate a review list of alarm number, current message, proposed message,
   current severity, proposed severity, and reason.
2. Review whether the alarm should pause, stop, or abort locally/globally.
3. Back up controller system variables before writing alarm metadata.
4. Generate a Robot Server alarm write plan containing only approved rows and
   exact `ComSet` URLs.
5. Dry-run the plan and show old message/severity, new message/severity, alarm
   number, and function code.
6. Execute only with a project approval phrase and readback verification.
7. Never alter the general error severity table as a shortcut for user alarm
   behavior.

Do not mix user alarm system-variable writes into the first comment writer.
Comments can be a normal generated metadata utility after list approval; user
alarms deserve their own explicit approval and rollback evidence.

Transport note: Robot Server is the first alarm message/severity writer because
it exposes the same operator-facing alarm page. SNPX is also proven capable of
writing severity on this controller: on 2026-05-20, `$UALRM_SEV[20]` was
projected with `SETASG 79 2 $UALRM_SEV[20] 1`, changed from `6` to `0`, and
confirmed by Robot Server. Keep that as a protected alarm-severity lane, not as
part of generic SNPX scratch writes. If SNPX is used for severity, use the
severity-specific tool path, which accepts only manual-confirmed enum values and
rejects nonzero upper byte/word readback.

SNPX message text is also proven possible on this controller. Projection
`SETASG 79 30 $UALRM_MSG[20] 1` wrote `SNPX MSG TEST`, and Robot Server
confirmed the message. The observed encoding is two ASCII characters per `%R`
word, low byte first. Keep Robot Server as the preferred user-alarm metadata
writer until the SNPX path has explicit string length, padding, character-set,
and rollback guards.

## Runtime Value Lane

Register values are runtime state, not metadata. Robot Server can read and write
numeric/string register values, but SNPX remains the preferred value interface
for runtime and commissioning work because it has project-owned ASG mapping,
typed encoding, allowlists, exact approval phrases, and readback gates. See
`docs\REGISTER_VALUE_INTERFACE_DECISION.md`.
