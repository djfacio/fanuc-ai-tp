# Rust Migration Plan

PowerShell remains the discovery and orchestration layer while the project is
still learning FANUC interfaces, controller quirks, and workflow boundaries.
Rust becomes the planned product core after a tool family has a stable contract.

This is not a rewrite mandate. Migrate only when Rust buys reliability,
testability, stronger typing, or safer write boundaries.

## Current Position

PowerShell is the right near-term default for:

- Calling Windows-native FANUC tools such as MakeTP, PrintTP, and KTRANS.
- Fast discovery against FTP, Robot Server HTTP, RoboGuide, and local files.
- Thin operator-facing workflow commands.
- Reading existing `.psd1` project configuration.
- Keeping iteration speed high while policies and interfaces are still moving.

Rust is the right long-term core for:

- Typed parsers and validators.
- Robot Server metadata snapshots, diffs, and write plans.
- SNPX protocol/client work.
- Evidence manifests and review packets.
- Deterministic program/spec generation.
- Safer command boundaries for live writes.

## Migration Trigger

Do not migrate a tool family just because Rust is available. Migrate when all of
these are true:

- The workflow has repeated several times without major redesign.
- Inputs and outputs are documented and represented as stable JSON or config.
- Safety gates are known.
- Failure modes are known enough to test.
- The Rust version can be behavior-compatible with the current tool.

## Target Architecture

```text
PowerShell wrapper or direct CLI
        |
        v
fanuc-ai-tp.exe
        |
        +-- metadata snapshot/diff/write-plan
        +-- SNPX read/write tools
        +-- spec validation
        +-- LS generation and safety parsing
        +-- manifest/review packet generation
        +-- upload/readback orchestration
```

PowerShell may remain as thin wrappers around the Rust CLI where that improves
operator ergonomics. It should not remain the home of large parsers once the
format is stable.

## First Migration Candidates

1. Robot Server metadata snapshot parser
   - Input: Robot Server `ComGet` HTML.
   - Output: stable metadata snapshot JSON.
   - Reason: HTML parsing and write-plan safety are better with typed tests.

2. Metadata diff and write-plan generator
   - Input: approved project comment/alarm list plus current snapshot.
   - Output: reviewable diff and blocked-by-default write plan.
   - Reason: this is where accidental writes must be hardest.

3. SNPX client consolidation
   - Input: SNPX read/write configs and generated plans.
   - Output: read/write evidence JSON.
   - Reason: the repo already has a Rust SNPX codec; protocol work belongs in
     Rust.

4. LS safety parser
   - Input: generated or decoded `.LS`.
   - Output: structured findings.
   - Reason: source safety gates should be deterministic and well tested.

5. Manifest and review packet builder
   - Input: validation, compile, round-trip, upload, readback evidence.
   - Output: manifest JSON and human review text.
   - Reason: evidence should be consistent across projects.

## Keep As PowerShell For Now

- MakeTP/PrintTP/KTRANS shell-out wrappers.
- One-off commissioning probes.
- Compatibility wrappers around stable Rust commands.
- Local glue for existing `.psd1` configs until Rust config loading is chosen.

## PCDK Boundary

PCDK is the main exception. It is COM/.NET-oriented. If PCDK becomes important
for metadata or controller evidence, prefer either:

- A small C#/.NET helper called by Rust; or
- A deliberately scoped PowerShell/.NET wrapper while the API is still being
  explored.

Do not force direct Rust COM integration unless the benefit is clear.

## Compatibility Rule

Every migrated Rust tool must preserve or intentionally version:

- Input shape.
- Output shape.
- Exit-code behavior.
- Evidence fields.
- Safety gates.
- Dry-run behavior.

The migration is successful when the Rust tool can replace the PowerShell tool
inside the existing workflow without weakening review, upload, or live-write
boundaries.
