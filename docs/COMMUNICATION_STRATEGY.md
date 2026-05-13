# Communication Strategy

This project should keep TP generation deterministic, while using richer controller interfaces for state, diagnostics, and guarded orchestration.

## Preferred Layers

1. FTP for file transfer and readback evidence.
2. PrintTP/MakeTP for compile/decode round trips.
3. SNPX for project-owned runtime register/IO contracts.
4. PCDK for Windows-side read-only controller introspection and evidence when FANUC libraries are installed.
5. KAREL TCP sockets for project-owned higher-level services when the controller option set allows it.
6. TP programs as the explicit robot-side execution artifacts, selected and verified by a human unless a later reviewed automation policy says otherwise.

## First Principles

- Do not hide robot state changes inside AI-generated text.
- Prefer read-only polling and inventory snapshots before writes.
- Keep every write path constrained by an address map, expected type, and review gate.
- Separate program generation from robot orchestration.
- Treat KAREL and SNPX as interfaces with their own manifests, tests, and safety rules.

## Interface Candidates

### SNPX

Best early use:

- Read registers and IO around generated-program tests.
- Verify marker registers such as `R[98]` or `R[99]`.
- Capture pre/post snapshots for pendant verification evidence.

Guardrails:

- Keep a checked-in address map.
- Default tools to read-only.
- Use SNPX V2 private per-connection `$SNPX_ASG` mapping on TCP `60008`.
- Program and verify the ASG map on every connection before trusting `%R` values.
- Keep the local wire-codec source in `vendor\snpx-codec\`; do not depend on another local project path.
- Require `config\snpx-writes.psd1` and `config\cell-map.psd1` approval before any write.
- Keep read-only snapshot tools separate from write command tools.
- Start from `config\cell-observations.psd1` and `generated\cell-status\latest\status-plan.md`.

### PCDK

Best use:

- Richer Windows-side tooling where FANUC libraries are available.
- Read-only controller snapshots for programs, alarms, tasks, frames, position registers, current position, IO, registers, and installed features.
- Filling or checking motion application specs before generation.
- RoboGuide vs physical controller comparison.

Guardrails:

- Keep PCDK-dependent tools isolated from the portable PowerShell-only workflow.
- Record library/version assumptions.
- Default to offline plan mode; require explicit `-ConnectReadOnly` before contacting a controller.
- Keep first-phase PCDK wrappers read-only and record `controllerWritesExecuted=false`.
- Do not use PCDK task control, program selection, FTP upload/delete, IO writes, frame updates, position records, or move-to behavior without a separate reviewed policy.

### KAREL TCP Socket Service

Best use:

- A small robot-side service that exposes project-specific read-only status or command requests.
- Message formats that are simpler and more stable than raw register conventions.

Guardrails:

- Start read-only.
- Use fixed JSON-line or delimited text messages.
- Validate command names and payloads.
- Do not start programs, change UOP, change system variables, or write motion state in the first service.

## Prototype Direction

The first prototype is a PC-side JSON-lines TCP client in `prototypes\tcp-json-bridge\`. It can connect, send one request, and wait for one line of response. This gives us a test harness before writing any KAREL server code.

Initial request shape:

```json
{"id":"1","type":"ping"}
```

Initial response shape:

```json
{"id":"1","ok":true,"controller":"R-30iB Plus"}
```

Next server-side step is a KAREL read-only echo/status service, compiled and tested in RoboGuide before touching the physical controller.
