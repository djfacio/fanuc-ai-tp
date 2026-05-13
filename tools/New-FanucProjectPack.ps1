param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [string]$ProjectName = "TestProject",
    [string]$WorkcellName = "Review and rename workcell",
    [string]$RobotIp = "192.168.5.10",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$toolchainRoot = Split-Path -Parent $scriptRoot

if ([System.IO.Path]::IsPathRooted($Path)) {
    $projectPath = $Path
} else {
    $projectPath = Join-Path (Get-Location).Path $Path
}

if ((Test-Path -LiteralPath $projectPath) -and -not $Force) {
    throw "Project pack already exists: $projectPath. Use -Force to update starter files."
}

$directories = @(
    $projectPath,
    (Join-Path $projectPath "applications"),
    (Join-Path $projectPath "config"),
    (Join-Path $projectPath "evidence"),
    (Join-Path $projectPath "generated"),
    (Join-Path $projectPath "generated\sources"),
    (Join-Path $projectPath "generated\compiled"),
    (Join-Path $projectPath "generated\jobs"),
    (Join-Path $projectPath "notes")
)

foreach ($directory in $directories) {
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
}

$projectManifestPath = Join-Path $projectPath "project.psd1"
$robotConfigPath = Join-Path $projectPath "config\robot.local.psd1"
$cellMapPath = Join-Path $projectPath "config\cell-map.psd1"
$controllerInventoryPath = Join-Path $projectPath "config\controller-inventory.local.psd1"
$gitignorePath = Join-Path $projectPath ".gitignore"
$readmePath = Join-Path $projectPath "README.md"
$processNotesPath = Join-Path $projectPath "notes\process.md"
$prMapPath = Join-Path $projectPath "notes\pr-map.md"
$exampleSpecPath = Join-Path $projectPath "applications\A_TEST_APR.motion-application.json"
$robotIniSourcePath = Join-Path $toolchainRoot "config\robot.ini"
$robotIniProjectPath = Join-Path $projectPath "config\robot.ini"

if ((Test-Path -LiteralPath $robotIniSourcePath) -and (-not (Test-Path -LiteralPath $robotIniProjectPath) -or $Force)) {
    Copy-Item -LiteralPath $robotIniSourcePath -Destination $robotIniProjectPath -Force
}

$projectManifest = @"
@{
    SchemaVersion = 1
    ProjectName = "$ProjectName"
    WorkcellName = "$WorkcellName"
    ToolchainPath = "$toolchainRoot"
    ApplicationRoot = "applications"
    OutputRoot = "generated"
    EvidenceRoot = "evidence"
    NotesRoot = "notes"
    Config = @{
        Robot = "config\robot.local.psd1"
        CellMap = "config\cell-map.psd1"
        ControllerInventory = "config\controller-inventory.local.psd1"
    }
}
"@

$gitignore = @"
# Project-local generated artifacts and sensitive/local config.
/generated/
/evidence/
/config/*.local.psd1
/config/robot.ini
"@

$robotConfig = @"
@{
    RobotIp = "$RobotIp"
    UserName = "anonymous"
    Password = "guest"
    WinOlpcVersion = "V9.40-1"
    MakeTpPath = "C:\Program Files (x86)\FANUC\WinOLPC\bin\maketp.exe"
    RobotIniPath = "robot.ini"
    CellMapPath = "cell-map.psd1"
    WorkcellRobotPath = "REVIEW_AND_SET_ROBOGUIDE_WORKCELL_ROBOT_PATH"
    ProgramPrefix = "A_"
    LegacyProgramPrefixes = @("AI_")
    KnownMacroPrograms = @()
}
"@

$cellMap = @"
@{
    SchemaVersion = 1
    PolicyScope = "project"
    ProjectName = "$ProjectName"
    WorkcellName = "$WorkcellName"
    Notes = "Project-local resource policy. Add only registers, IO, and CALL targets reviewed for this workcell."

    RegisterWrites = @{
        AllowedRanges = @()
        Allowed = @()
    }

    IoWrites = @{
        AllowedRanges = @()
        Allowed = @()
    }

    Calls = @{
        Allowed = @()
        Notes = "No generated CALL targets are approved yet."
    }
}
"@

$controllerInventory = @"
@{
    SchemaVersion = 1
    ProjectName = "$ProjectName"
    WorkcellName = "$WorkcellName"
    Notes = "Local ignored controller inventory placeholder. Fill with real controller/tool capability details as needed."
    Controller = @{
        Model = "REVIEW_AND_SET"
        SoftwareVersion = "REVIEW_AND_SET"
        RobotIp = "$RobotIp"
    }
    Tooling = @{
        WinOlpc = `$true
        RoboGuide = `$true
        Pcdk = `$false
        Snpx = `$false
    }
    LiveOperations = @{
        FtpUploadEnabled = `$false
        SnpxWritesEnabled = `$false
        PcdkWritesEnabled = `$false
    }
}
"@

$readme = @"
# $ProjectName

Project pack for FANUC AI TP generation work.

This folder is intentionally separate from the public toolchain:

```text
$toolchainRoot
```

Use this project for real application specs, project-local config, generated LS/TP outputs, and evidence.

## Typical Commands

From the toolchain folder:

```powershell
cd "$toolchainRoot"
.\tools\Invoke-FanucMotionWorkflow.ps1 ``
  -ProjectPath "$projectPath" ``
  -SpecPath .\applications\A_TEST_APR.motion-application.json ``
  -Force
```

## Project-Owned Items

- PR values and touchups
- UFRAME / UTOOL / payload setup
- IO meanings and safe states
- physical run decisions
- project-specific review notes

Tool gates track generation, compile, round-trip, review, upload, and readback evidence.
"@

$processNotes = @"
# Process Notes

Record process intent, assumptions, tooling notes, and operator-owned run decisions here.
"@

$prMap = @"
# PR Map

| PR | Name | Purpose | Source | Notes |
| --- | --- | --- | --- | --- |
| PR[300] | APPROACH | Review before use | Operator-owned | |
| PR[301] | PROCESS | Review before use | Operator-owned | |
| PR[302] | RETRACT | Review before use | Operator-owned | |
"@

$exampleSpec = @"
{
  "schemaVersion": 1,
  "applicationName": "$ProjectName first APR path",
  "programName": "A_TEST_APR",
  "phase": "generation-ready",
  "purpose": "Project-local starter motion through reviewed approach, process, and retract PR targets.",
  "cellContext": {
    "controller": "REVIEW_AND_SET",
    "robot": "REVIEW_AND_SET",
    "workcell": "$WorkcellName",
    "process": "Starter APR path",
    "payloadName": "REVIEW_AND_SET"
  },
  "policy": {
    "cellMapPolicy": "config/cell-map.psd1",
    "motionAuthority": "reviewed-motion-template",
    "humanReviewRequired": true,
    "productionOverwriteAllowed": false
  },
  "resources": {
    "userFrame": { "number": 1, "name": "UFRAME 1", "source": "Operator-owned project frame", "verified": true },
    "userTool": { "number": 1, "name": "UTOOL 1", "source": "Operator-owned project tool", "verified": true },
    "payload": { "number": 1, "name": "Payload schedule 1", "source": "Operator-owned project payload", "verified": true },
    "points": [
      { "name": "APPROACH", "source": "position-register", "verified": true, "touchupRequired": false },
      { "name": "PROCESS", "source": "position-register", "verified": true, "touchupRequired": false },
      { "name": "RETRACT", "source": "position-register", "verified": true, "touchupRequired": false }
    ],
    "io": [],
    "registers": [],
    "calls": []
  },
  "motionPlan": {
    "motionTypes": ["J", "L"],
    "speedPolicy": "Low-speed joint approach and controlled linear process/retract moves.",
    "terminationPolicy": "Use FINE for first-pass review.",
    "approachRetract": "APPROACH establishes clearance, PROCESS is the work point, RETRACT exits to clearance.",
    "clearancePolicy": "Operator owns physical path clearance before upload/run.",
    "recoveryPlan": "Stop, hold position, and recover manually if path or setup does not match expectation.",
    "motionSequence": [
      {
        "stepName": "APPROACH",
        "motionType": "J",
        "target": { "type": "position-register", "number": 300, "name": "APPROACH", "source": "Operator-owned reviewed PR[300]", "verified": true },
        "speed": { "value": 10, "unit": "%" },
        "termination": { "type": "FINE" }
      },
      {
        "stepName": "PROCESS",
        "motionType": "L",
        "target": { "type": "position-register", "number": 301, "name": "PROCESS", "source": "Operator-owned reviewed PR[301]", "verified": true },
        "speed": { "value": 100, "unit": "mm/sec" },
        "termination": { "type": "FINE" }
      },
      {
        "stepName": "RETRACT",
        "motionType": "L",
        "target": { "type": "position-register", "number": 302, "name": "RETRACT", "source": "Operator-owned reviewed PR[302]", "verified": true },
        "speed": { "value": 100, "unit": "mm/sec" },
        "termination": { "type": "FINE" }
      }
    ]
  },
  "safety": {
    "dcsReviewed": true,
    "interlocksReviewed": true,
    "operatorLocationReviewed": true,
    "faultHandlingReviewed": true,
    "noControllerConfigWrites": true,
    "notes": "Tool gates cover generation, compile, round-trip, upload, and readback only."
  },
  "evidence": {
    "roboguideRequired": false,
    "roboguidePlan": "Optional RoboGuide/manual notes can be recorded when useful.",
    "operatorRunPlan": "Operator owns robot mode, setup, and physical run decisions.",
    "snapshotPlan": "Optional before/after notes may be recorded for the project.",
    "acceptanceCriteria": [
      "Generated LS references only reviewed PR targets.",
      "Generated LS selects only reviewed UFRAME, UTOOL, and PAYLOAD.",
      "Generated LS contains no generated Cartesian /POS records."
    ]
  },
  "generation": {
    "allowed": true,
    "mode": "reviewed-motion-template",
    "templateId": "approach-process-retract-v1",
    "notes": "Project-local starter spec."
  }
}
"@

$files = @(
    @{ Path = $gitignorePath; Content = $gitignore },
    @{ Path = $projectManifestPath; Content = $projectManifest },
    @{ Path = $robotConfigPath; Content = $robotConfig },
    @{ Path = $cellMapPath; Content = $cellMap },
    @{ Path = $controllerInventoryPath; Content = $controllerInventory },
    @{ Path = $readmePath; Content = $readme },
    @{ Path = $processNotesPath; Content = $processNotes },
    @{ Path = $prMapPath; Content = $prMap },
    @{ Path = $exampleSpecPath; Content = $exampleSpec }
)

foreach ($file in $files) {
    if ((Test-Path -LiteralPath $file.Path) -and -not $Force) {
        continue
    }
    $file.Content | Set-Content -LiteralPath $file.Path -Encoding ASCII
}

[pscustomobject]@{
    ProjectName = $ProjectName
    ProjectPath = (Get-Item -LiteralPath $projectPath).FullName
    ManifestPath = (Get-Item -LiteralPath $projectManifestPath).FullName
    StarterSpecPath = (Get-Item -LiteralPath $exampleSpecPath).FullName
    ToolchainPath = $toolchainRoot
}
