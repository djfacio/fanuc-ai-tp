# Template Catalog

The template catalog is the reviewed list of deterministic FANUC TP program
patterns currently supported by this project.

## Files

```text
config/template-catalog.psd1
tools/Test-FanucTemplateCatalog.ps1
tools/Get-FanucTemplateCatalog.ps1
```

Each catalog entry declares:

- template id
- generated/example program name
- spec type
- reviewed motion template id, when applicable
- example spec path
- motion class
- allowed operation types
- declared register, IO, call, and position-register resources
- required evidence
- current status

Most proven-live templates are no-motion. The first motion catalog entry is
`pr-waypoint-sequence-v1`, which is offline validated only. It references
reviewed PR targets and remains gated by motion application validation,
generated LS/spec matching, MakeTP, PrintTP round-trip, RoboGuide evidence, and
operator-owned physical verification before any run/release decision.

## Commands

Validate the catalog:

```powershell
.\tools\Test-FanucTemplateCatalog.ps1
```

Generate JSON and Markdown catalog artifacts:

```powershell
.\tools\Get-FanucTemplateCatalog.ps1 -WriteMarkdown
```

The validator also checks that every example program spec is cataloged, every
cataloged example exists, program names match, no-motion examples do not allow
motion, motion examples are generation-ready, and example operations/resources
stay within the declared template contract.
