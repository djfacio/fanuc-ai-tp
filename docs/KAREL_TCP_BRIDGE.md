# KAREL TCP Bridge Strategy

The KAREL TCP bridge is a future option, not the current default. The project
already has narrower interfaces for the work we have proven:

- FTP for compiled TP artifact transfer and readback.
- SNPX V2 for reviewed status marker reads/writes through private ASG mapping.
- RoboGuide for simulation evidence.

KAREL TCP should be used only when those interfaces cannot express the needed
workflow safely.

## Current Position

`config/interface-strategy.psd1` keeps `karel-tcp-bridge` disabled. It may be
enabled only after robot-resident code, message schemas, deployment, rollback,
and tests are reviewed.

The proposed bridge shape is newline-delimited JSON over TCP:

- `status.snapshot.request`
- `status.snapshot.response`
- `command.reviewed-write.request`
- `command.reviewed-write.response`

Write-capable messages must stay reviewed-command messages with approval phrase,
allowlist, sequence id, audit log, and before/after evidence.

## Commands

Validate the strategy:

```powershell
.\tools\Test-FanucInterfaceStrategy.ps1
```

Generate JSON and Markdown strategy artifacts:

```powershell
.\tools\Get-FanucInterfaceStrategy.ps1 -WriteMarkdown
```

## Rules

- Do not let the physical KAREL bridge run programs.
- Do not let the physical KAREL bridge command robot motion.
- Keep read/status messages separate from reviewed command messages.
- Keep writes tied to the same safety model as SNPX writes: allowlist, exact
  approval, pre-read, post-read, and restoration when required.
- Keep deployment and rollback explicit before writing robot-resident code.
