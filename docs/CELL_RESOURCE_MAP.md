# Cell Resource Map

`config\cell-map.psd1` is the reviewed allowlist for generated specs.

The spec validator now checks:

- Register writes are limited to approved marker registers.
- IO writes are limited to approved signals and safe states.
- Generated `CALL` targets are blocked unless explicitly allowlisted.

This matters because a syntactically valid TP program can still touch the wrong robot resource. The map gives us a project-owned contract between planning, generation, review, and robot execution.

## Current Allowlist

Register writes:

- `R[90]`, `R[91]` for `AI_REGDIAG`
- `R[97]` for `AI_CELLCHK`
- `R[98]` for `AI_SNAPSHOT`
- `R[99]` for `AI_HELLO`

IO writes:

- `DO[1]` ON/OFF for the reviewed `AI_IODIAG` pulse test

CALL targets:

- None approved yet

## Policy

- Add to the map only after reviewing the actual cell resource and recovery behavior.
- Prefer named, narrow entries over broad ranges.
- Do not use the map to justify motion. Motion still requires RoboGuide evidence, frame/tool/payload assumptions, and T1 verification.
- Do not add production program calls until the called program behavior is understood and documented.
