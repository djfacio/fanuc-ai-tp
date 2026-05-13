# Template Roadmap

This roadmap is based on the first 25 read-only decoded production programs from robot `MD:`. It is intentionally conservative: learn existing cell structure first, then generate constrained replacements or helpers.

## Observed Families

### Orchestration

Examples:

- `BNEMAIN`
- `F_CONV_DROP`

Traits:

- Uses `CALL` instructions to coordinate smaller routines.
- May combine IO, simple moves, and utility routines.

Template direction:

- Generate a reviewed sequence skeleton with named steps.
- Keep called production programs explicit.
- Require a call allowlist before generation.

### Motion Routines

Examples:

- `BNEPICK`
- `BNEPLACE`
- `BNEREGRIP`
- `F_ENTER_CNC`
- `F_EXIT_CNC`

Traits:

- Contains a small number of `J`/`L` motion lines.
- Usually belongs to a specific fixture, frame, tool, and payload context.

Template direction:

- Do not generate free-form motion yet.
- First template should reference existing named PRs or taught points only.
- Keep optional RoboGuide evidence separate from operator-owned frame/tool/payload and physical run decisions.

### Calculation Helpers

Examples:

- `F_CALC_CNC`
- `F_CALC_PICK`
- `F_CALC_POS`
- `F_CALC_REGRIP`

Traits:

- No motion.
- Heavy register or position-register logic.

Template direction:

- Build spec support for register/PR calculations.
- Add round-trip checks for arithmetic and assignment patterns.
- Keep writes limited to an allowlisted register/PR range.

### IO Utilities

Examples:

- `F_BG_HMI`
- `F_FEEDER`
- `F_FINISH_CYCLE`
- `F_CONVEYOR`
- `BLOWER_TEST`

Traits:

- No motion.
- Output writes and status signaling.

Template direction:

- Build an IO map before generating more IO writes.
- Require signal names, expected normal state, failure state, and manual recovery notes.

## Next Implementation Order

1. Add an IO/register map file and validators.
2. Add a `callSequence` operation type guarded by an allowlist.
3. Add PR/register calculation operations.
4. Add RoboGuide test-plan generation for IO and CALL templates.
5. Only then add constrained motion templates.

Status:

- Step 1 has started with `config\cell-map.psd1` and `tools\Test-FanucCellMap.ps1`.
- Specs now fail validation when they write unapproved registers, write unapproved IO, or call unapproved programs.
- `tools\Get-FanucProductionResourceReport.ps1 -WriteMarkdown` now extracts CALL, IO, and register candidates from decoded production programs for review before map expansion.
