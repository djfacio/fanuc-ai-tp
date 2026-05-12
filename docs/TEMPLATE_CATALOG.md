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
- example spec path
- motion class
- allowed operation types
- declared register, IO, and call resources
- required evidence
- current status

All current templates are no-motion. Motion templates should not be added as
usable catalog entries until the motion review, RoboGuide/T1 validation, frame,
tool, speed, payload, and recovery requirements are explicit.

## Commands

Validate the catalog:

```powershell
.\tools\Test-FanucTemplateCatalog.ps1
```

Generate JSON and Markdown catalog artifacts:

```powershell
.\tools\Get-FanucTemplateCatalog.ps1 -WriteMarkdown
```

The validator also checks that every example spec is cataloged, every cataloged
example exists, the program names match, no-motion examples do not allow motion,
and example operations/resources stay within the declared template contract.
