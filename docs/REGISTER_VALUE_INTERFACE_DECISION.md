# Register Value Interface Decision

This project has two practical routes for numeric and string register values:

| Route | Best use | Why |
| --- | --- | --- |
| SNPX V2 | Runtime reads/writes, status snapshots, commissioning proofs, HMI-style interaction | Typed projection, batch reads/writes, private per-connection mapping, explicit allowlist, existing readback gates |
| Robot Server | Low-rate inspection, metadata pages, occasional human-reviewed value checks | Simple HTTP GET pages, no ASG setup, easy evidence capture |

## Decision

Keep SNPX as the preferred register value read/write path for runtime and test
work. Use Robot Server for metadata and low-rate inspection unless a future
project proves a narrow Robot Server value writer is safer for a specific case.

## Reasoning

Robot Server exposes numeric register values on `/KAREL/ComGet?sFc=28` and
string register values on `/KAREL/ComGet?sFc=30`. Its JavaScript also exposes
value writes through:

| Function | Meaning |
| ---: | --- |
| `2` | Numeric register value |
| `15` | String register value |

That is useful, but it is still an operator-web-page style interface. Writes are
plain HTTP GET requests and are not naturally grouped with the project's
register/IO runtime policies.

SNPX already has the safety shape we want for values:

- Project-owned allowlist in `config\snpx-writes.psd1`.
- Private per-connection `$SNPX_ASG` mapping.
- ASG readback before trusting the projection.
- Encoded value evidence.
- Exact approval phrase for live writes.
- Post-write readback.
- Restoration gates for outputs.

Robot Server value writes may still be useful for future one-off service tools,
but they should not become the default runtime path.

## Current Policy

- Register comments: Robot Server comment tools.
- User alarm message/severity: Robot Server alarm tools.
- Numeric register values: SNPX by default.
- String register values: prefer SNPX if mapped and tested; otherwise plan a
  specific proof before using Robot Server `sFc=15`.
- Generated TP may write project-approved registers explicitly when the program
  logic owns the value.

Do not mix register value writes into metadata writers. A tool that changes a
runtime value must be reviewed as a command/write tool, not as a documentation
tool.
