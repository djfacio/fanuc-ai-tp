# Contributing

This project builds tools for AI-assisted FANUC TP program planning, generation,
validation, and deployment evidence. Contributions are welcome, but robot-facing
changes need a higher bar than normal application code.

## Safety First

- Do not add behavior that auto-runs robot programs.
- Do not bypass the `AI_` program-name prefix rule.
- Do not weaken the `.LS` filename and `/PROG` header match check.
- Do not add unreviewed register, IO, or `CALL` targets to `config/cell-map.psd1`.
- Do not add live robot writes without an allowlist, value validation, dry-run
  plan, explicit human approval gate, pre-read/write/post-read evidence, and a
  clear restoration path for outputs.
- Do not commit generated robot evidence, downloaded robot programs, logs,
  packet captures, or local credentials.
- Keep motion generation behind explicit design review, documented frames/tools,
  speed and payload assumptions, RoboGuide/T1 validation, and operator approval.

## Local Checks

Run the offline PowerShell validator suite:

```powershell
.\tools\Invoke-FanucToolTests.ps1
```

Run the vendored SNPX codec tests:

```powershell
cargo test --manifest-path .\vendor\snpx-codec\Cargo.toml
```

The CI workflow runs these same offline checks. It does not connect to a robot,
RoboGuide, FTP, or SNPX endpoint.

## Development Notes

- Prefer structured program specs and deterministic emitters over direct freeform
  LS generation.
- Keep live-cell configuration local and reviewed. Public examples should be
  safe placeholders or clearly marked commissioning examples.
- Keep generated files under `generated/`, robot downloads under `downloaded/`,
  and logs under `logs/`; these paths are ignored by Git.
- If a change touches upload, SNPX writes, safety gates, or production-program
  analysis, include focused tests or a documented manual evidence path.
