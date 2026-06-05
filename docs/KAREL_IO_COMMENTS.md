# KAREL IO Comment Utilities

KAREL is a proven fallback route for writing controller metadata such as
register comments and IO comments. It is close to the controller data model, but
it should not be the default for project-wide metadata if Robot Server HTTP or
PCDK can provide the same behavior with cleaner PC-side tooling.

This note covers comments only. It does not grant permission to write IO values,
change IO assignments, change IO modes, simulate IO, run programs, or move the
robot.

## Local Manual Basis

Local manual `b-83144en-1-02` supports the IO-comment route:

- Page 348: `SET_PORT_CMT(port_type, port_no, comment_str, status)` sets the
  comment displayed on the teach pendant for a logical port. It belongs to
  `%ENVIRONMENT Group: IOSETUP`.
- Page 252: `GET_PORT_CMT(port_type, port_no, comment_str, status)` reads the
  comment for a logical port and returns status zero when valid.
- Page 347: FANUC example uses `SET_PORT_CMT(IO_DOUT, 1, 'Equip -READY ',
  STATUS)` to set a digital output comment.

The installed WinOLPC include file `kliotyps.kl` defines the port type
constants used by those built-ins.

## Supported Port Families

The first generated utility should support these comment families:

| Pendant family | KAREL constant | Constant value | Meaning |
| --- | --- | ---: | --- |
| `DI[n]` | `IO_DIN` | 1 | Digital input |
| `DO[n]` | `IO_DOUT` | 2 | Digital output |
| `RI[n]` | `IO_RDI` | 8 | Robot digital input |
| `RO[n]` | `IO_RDO` | 9 | Robot digital output |
| `GI[n]` | `IO_GPIN` | 18 | Group input |
| `GO[n]` | `IO_GPOUT` | 19 | Group output |
| `UI[n]` | `IO_UOPIN` | 20 | User operator panel input |
| `UO[n]` | `IO_UOPOUT` | 21 | User operator panel output |

`RI` and `RO` are not aliases for `DI` and `DO`. Treat Robot Input and Robot
Output as their own port families so comments do not accidentally land on the
wrong IO screen.

`GI` and `GO` are not aliases for `DI` and `DO` either. `KLIOTYPS.KL` also
defines `IO_GPIN32` and `IO_GPOUT32`; use those only when the reviewed list
explicitly targets the 32-bit group IO family.

Other comment families such as analog IO, flags, markers, and tool IO can be
added later by policy, but they should not be enabled by accident.

## Utility Design

If KAREL is used, the first utility should be a reviewed KAREL program, for
example `A_IOCMT.KL`, with these constraints:

- `%NOLOCKGROUP`
- `%ENVIRONMENT IOSETUP`
- `%INCLUDE KLIOTYPS`
- Use `GET_PORT_CMT` before every write to capture the existing comment.
- Use `SET_PORT_CMT` only for allowlisted port/comment rows.
- Use `GET_PORT_CMT` after every write to verify the result.
- Write a concise status line for each attempted comment.
- Do not call `SET_PORT_VAL`, `SET_PORT_ASG`, `SET_PORT_MOD`, or any other IO
  value/configuration writer.
- Do not write `DOUT[...]`, `RDO[...]`, `UO[...]`, flags, markers, registers, PRs,
  frames, tools, payloads, or system variables.

The caller may be a no-motion TP wrapper, similar to `A_SETCMT`, but Codex must
not run it from PC tooling. The operator owns execution from the pendant unless
a future project policy explicitly creates a safe remote-run path.

## Workflow

1. Define desired comments in a project-local metadata plan, such as
   `config\comment-map.sample.psd1`.
2. Snapshot current comments with `GET_PORT_CMT` or another read-only evidence
   layer.
3. Generate a diff showing old comment, new comment, port family, and port
   number.
4. Generate `A_IOCMT.KL` from the approved diff.
5. Compile with KTRANS, upload the `.PC`, and upload a no-motion caller if
   needed.
6. Operator runs the caller from the pendant.
7. Verify comments with `GET_PORT_CMT` readback or pendant inspection.

Do not bulk-overwrite IO comments from guessed names. IO comments are
production-facing maintenance documentation; losing a useful existing label is a
real regression even if no signal value changes.
