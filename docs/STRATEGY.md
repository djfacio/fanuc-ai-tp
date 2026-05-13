# FANUC AI TP Strategy

This project is an AI-assisted workflow for planning, generating, testing, and deploying FANUC robot TP programs for an R-30iB Plus class controller.

The durable source of truth is not a raw `.LS` file. The durable source of truth is a reviewed program specification plus the evidence created as that specification moves through generation, validation, compilation, simulation, upload, and manual verification.

## Principles

- Keep AI in the planning and drafting loop, but keep robot-facing artifacts deterministic and reviewable.
- Generate `.LS` from constrained templates or structured specs whenever possible.
- Treat `.TP` files as compiled build artifacts.
- Keep RoboGuide available as the high-fidelity simulator, while building project-owned wrappers and validators around it.
- Prefer explicit safety contracts over implicit trust in generated code.
- Require human review before any motion, controller-side services, KAREL, sockets, SNPX writes, system variable changes, DCS edits, UOP behavior, or production-program interaction.

## Workflow Model

```text
intent -> spec -> static validation -> LS generation -> LS validation
       -> MakeTP compile -> PrintTP round-trip -> RoboGuide test
       -> FTP upload -> readback evidence -> operator-owned release decision
```

## Tooling Roles

- `tools/`: PowerShell entry points for generation, validation, compilation, upload, download, and inspection.
- `schemas/`: Machine-checkable specs for generated program plans.
- `docs/`: Operating rules, safety policy, workflow design, and implementation notes.
- `generated/`: Output artifacts. Treat these as reproducible products of specs and tools.
- `downloaded/`: Robot-readback artifacts for inspection and comparison.
- `logs/`: Upload and validation records.

## Interface Strategy

- FTP is for file transfer, backups, readback, and upload records.
- WinOLPC MakeTP and PrintTP are for compile and round-trip checks.
- RoboGuide is for simulation, cycle observation, and regression-style manual or scripted checks.
- SNPX is for explicit live register, IO, and status interactions where read/write scope is constrained.
- PCDK is an option for richer controller integration after the core workflow is stable.
- KAREL and TCP sockets are powerful but should be treated as reviewed controller-side infrastructure, not casual generated output.

## Near-Term Buildout

1. Extract shared validators from build scripts.
2. Define the first program spec schema.
3. Generate no-motion and IO/register utilities from specs.
4. Expand round-trip comparison beyond `/MN` instructions as more program features are supported.
5. Add RoboGuide evidence notes and, later, automation hooks.
6. Add optional RoboGuide/manual evidence records while keeping robot-side physical verification operator-owned.
