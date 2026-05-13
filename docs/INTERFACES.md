# Controller Interface Strategy

This project can use several FANUC controller interfaces. Each interface has a different risk profile.

## FTP

Use for file transfer, backup, upload, and robot readback verification. FTP does not run programs by itself.

Required gates before upload:

- Spec validation.
- LS safety validation.
- MakeTP compile.
- PrintTP round-trip.
- Manifest local evidence.
- Human review.

## WinOLPC MakeTP and PrintTP

Use MakeTP to compile `.LS` into `.TP`. Use PrintTP to decode `.TP` and prove the compiled artifact still represents the intended instructions.

## RoboGuide

Use as the high-fidelity simulation environment. Automation can come later; manual evidence should be recorded now with `Set-FanucSimulationEvidence.ps1`.

## SNPX

Use SNPX for explicit live register, IO, and status reads/writes only after a reviewed address map exists.

The project-owned SNPX read plan is `config\snpx-readonly.psd1`. The project-owned SNPX write allowlist is `config\snpx-writes.psd1`. Both use SNPX V2, TCP `60008`, and private per-connection `$SNPX_ASG` projection into `%R`. The local codec source for future live reads and writes is in `vendor\snpx-codec\`.

Rules:

- Prefer reads first.
- Program `CLRASG` and `SETASG` per connection, then verify `$SNPX_ASG` by readback.
- Treat unassigned `%R` zero values as a mapping failure until proven otherwise.
- Make write scopes narrow and documented.
- Keep snapshot reads and command writes as separate tools.
- Never use SNPX writes as hidden program behavior.
- Record live-write tests separately from generated TP evidence.

## PCDK

PCDK is the richer Windows-side integration layer for controller state and evidence when FANUC libraries are installed. Keep it behind wrappers so safety gates remain project-owned.

The first project wrapper is `tools\New-FanucPcdkSnapshot.ps1`, configured by `config\pcdk-snapshot.psd1`. It is read-only by default and produces artifacts that conform to `schemas\controller-snapshot.schema.json`.

Rules:

- Default to offline plan mode.
- Require explicit `-ConnectReadOnly` before contacting a controller.
- Record `liveRobotCommandsExecuted=true` for live reads.
- Always record `controllerWritesExecuted=false`.
- Do not use PCDK to select/run programs, pause/continue/abort tasks, write IO, simulate IO, change IO config, update frames, record positions, move to positions, upload/delete files, or save/delete programs in the first PCDK track.
- Use PCDK snapshots to support motion application specs, not bypass their readiness gates.

## KAREL and TCP Sockets

KAREL and socket services are controller-side infrastructure, not casual generated output. Treat them like production software:

- Separate review.
- Separate deployment process.
- Explicit command protocol.
- Authentication/network assumptions.
- Fail-safe behavior.
- Pendant/operator visibility.
