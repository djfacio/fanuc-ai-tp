# Controller Inventory

The controller inventory records what a specific cell and local workstation can
actually support. It is intentionally separate from robot-facing scripts so that
workflows can make capability decisions from explicit facts instead of hidden
assumptions.

## Files

```text
config/controller-inventory.sample.psd1
config/controller-inventory.local.psd1
```

The sample file is safe to publish and keeps every live capability disabled.
Copy it to `config/controller-inventory.local.psd1` for a real cell. The local
file is ignored by Git.

## Validate

```powershell
.\tools\Test-FanucControllerInventory.ps1
.\tools\Test-FanucControllerInventory.ps1 -InventoryPath .\config\controller-inventory.local.psd1
```

The validator checks required sections, supported SNPX mode, port ranges,
policy/tool consistency, and the project rule that human approval remains
required.

## Summarize Capabilities

```powershell
.\tools\Get-FanucControllerCapability.ps1
.\tools\Get-FanucControllerCapability.ps1 -InventoryPath .\config\controller-inventory.local.psd1
```

The capability summary reports:

- `CanCompileTp`
- `CanUploadTp`
- `CanReadTp`
- `CanUseSnpx`
- `CanWriteSnpx`
- `CanUseKarelBridge`
- `CanRunRoboguideEvidence`
- `RequiresHumanApproval`

Future workflow tools should use this summary before enabling compile, upload,
readback, SNPX, KAREL bridge, or RoboGuide evidence paths.
