# Cell Resource Map

`config\cell-map.psd1` is the reviewed allowlist for generated specs.

The spec validator now checks:

- Register writes are limited to approved scratch ranges or named marker registers.
- IO writes are limited to approved scratch ranges or named signals and safe states.
- Generated `CALL` targets are blocked unless explicitly allowlisted.

This matters because a syntactically valid TP program can still touch the wrong robot resource. The map gives us a project-owned contract between planning, generation, review, and robot execution.

## Current Allowlist

Register writes:

- User-approved scratch range: `R[90]` through `R[99]`
- `R[90]`, `R[91]` for `AI_REGDIAG`
- `R[97]` for `AI_CELLCHK`
- `R[98]` for `AI_SNAPSHOT`
- `R[99]` for `AI_HELLO`

IO writes:

- User-approved scratch range: `DO[1]` through `DO[80]`, ON/OFF
- `DO[1]` ON/OFF for the reviewed `AI_IODIAG` pulse test

CALL targets:

- None approved yet

## Policy

- Add to the map only after reviewing the actual cell resource and recovery behavior.
- Keep `R[90]`-`R[99]` and `DO[1]`-`DO[80]` as the only free scratch write ranges unless the user explicitly expands them.
- Treat production/status registers such as `R[103]`, `R[107]`, and `R[110]`, and outputs above `DO[80]`, as read-only until separately approved.
- Prefer named entries for generated templates even when they fall inside an approved scratch range.
- Do not use the map to justify motion. Motion still requires RoboGuide evidence, frame/tool/payload assumptions, and T1 verification.
- Do not add production program calls until the called program behavior is understood and documented.
