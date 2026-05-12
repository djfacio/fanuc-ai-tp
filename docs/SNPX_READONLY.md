# SNPX Read-Only Snapshot

This project uses SNPX V2 on the FANUC HMI/CIMPLICITY-style endpoint, TCP `60008`, with a private per-connection `$SNPX_ASG` mapping.

This document covers status snapshots, which stay read-only. SNPX writes are a separate allowlisted path documented in `docs\SNPX_WRITES.md`.

## Local Files

```text
config\snpx-readonly.psd1
tools\Test-FanucSnpxReadonlyConfig.ps1
tools\Get-FanucSnpxAddressMap.ps1
tools\Get-FanucSnpxCommissioningMatrix.ps1
tools\Invoke-FanucSnpxReadSnapshot.ps1
vendor\snpx-codec\
```

`vendor\snpx-codec\` is the local Rust SNPX/SRTP codec source for future live reads. Keep SNPX implementation material in this repo; do not depend on another local project path being present.

## Mapping Model

SNPX does not read a FANUC item such as `R[97]` or `DO[1]` directly on the wire. The controller projects robot data into GE-style PLC memory areas such as `%R`, `%I`, `%Q`, `%AI`, and `%AQ`.

For this project, the read plan uses:

- Protocol: `SNPX_V2`
- Mapping mode: `per-connection`
- Assignment mode: `project-owned-asg`
- Robot IP: `192.168.5.10`
- Port: `60008`
- Projection area: `%R`
- ASG slot cap: `80`

Live code must perform this sequence:

1. Connect to TCP `60008`.
2. Probe `$SNPX_PARAM.$VERSION`.
3. Probe `$SNPX_PARAM.$NUM_CIMP`.
4. Run `CLRASG` to create the private per-connection assignment table.
5. Run `SETASG` for each row in `config\snpx-readonly.psd1`.
6. Read back `$SNPX_ASG` and fail closed if any slot differs.
7. Read the projected `%R` window.

Unassigned `%R` reads can return `0`, so ASG readback verification is not optional.

Fractional robot registers need explicit scaling. `R[110]` is read-only and is configured with `SETASG` multiply `1000` plus `ScaleDivisor = 1000` so values such as `21.209` are preserved in snapshots.

## Commands

Validate the config:

```powershell
.\tools\Test-FanucSnpxReadonlyConfig.ps1
```

Generate the address map:

```powershell
.\tools\Get-FanucSnpxAddressMap.ps1 -WriteMarkdown
```

Generate the commissioning matrix with read/write/restoration status and projection collision checks:

```powershell
.\tools\Get-FanucSnpxCommissioningMatrix.ps1 -WriteMarkdown
```

Emit a plan-only values file shaped for the status snapshot tool:

```powershell
.\tools\Invoke-FanucSnpxReadSnapshot.ps1 -PlanOnly
```

Generate the live-read command/evidence plan without touching the robot:

```powershell
.\tools\Invoke-FanucSnpxLiveRead.ps1
```

Execute the live read only after reviewing the emitted `CLRASG` / `SETASG` commands:

```powershell
.\tools\Invoke-FanucSnpxLiveRead.ps1 -Execute -AcceptAsgSetup
```

Create a snapshot from that values file:

```powershell
.\tools\New-FanucCellStatusSnapshot.ps1 -Label snpx-plan -ValuesPath .\generated\cell-status\snpx-values.json -Force
```

## Live Read Gate

Before enabling live reads:

- Build and test the local `vendor\snpx-codec` crate in this repo.
- Implement a project-owned live reader around that codec.
- Keep the status path read-only.
- Program and verify the private ASG map on every connection.
- Record live-read evidence separately from generated TP upload evidence.
- Do not add SNPX writes to snapshot tooling.
