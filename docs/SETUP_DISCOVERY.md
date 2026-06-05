# Setup Discovery

Do not rely on another AI or new user guessing where FANUC tooling is installed.
Use the project setup tools and review the generated config before live work.

## Dependency Levels

Most repository work is offline and does not require FANUC software:

- review and edit specs, rules, schemas, docs, and project packs
- validate JSON/specs/cell maps
- generate `.LS` source
- run offline PowerShell tests
- run the vendored Rust SNPX codec tests
- plan Robot Server comments/alarms and SNPX address/write maps

WinOLPC is needed when a workflow compiles or decodes TP artifacts:

- `MakeTP` compile from `.LS` to `.TP`
- `PrintTP` decode from `.TP` to `.LS`
- round-trip evidence
- upload-ready local workflow gates

RoboGuide is optional unless a specific project policy makes simulation evidence
a gate. It may provide the workcell robot path used by `robot.ini`, but offline
planning and LS generation can proceed without it.

PCDK is optional and read-only by default. It is not required for normal spec,
generation, compile, FTP, SNPX, or Robot Server workflows.

## Required Local Inputs For Live Or Compile Workflows

Each robot/workcell needs its own local robot config:

- controller IP address
- FTP user/password policy
- WinOLPC `MakeTP` path, when compiling or decoding
- project `robot.ini` path, when compiling or decoding
- RoboGuide workcell robot path, when RoboGuide evidence is used
- project cell-map/resource policy

## Generate A Local Robot Config

Run:

```powershell
.\tools\New-FanucRobotConfig.ps1 `
  -OutputPath .\config\robot.local.psd1 `
  -RobotIp 192.0.2.10
```

The tool searches common WinOLPC locations for `maketp.exe` and searches the
current user's Documents folder for RoboGuide `My Workcells\...\Robot_*`
folders that contain `support` and `output`.

Then open `config\robot.local.psd1` and review every value. Replace placeholder
values such as `REVIEW_AND_SET_MAKETP_PATH` before compiling or decoding, and
replace `REVIEW_AND_SET_ROBOGUIDE_WORKCELL_ROBOT_PATH` before using RoboGuide
evidence.

Use the local config explicitly:

```powershell
.\tools\Invoke-FanucLocalWorkflow.ps1 `
  -SpecPath .\examples\AI_HELLO.program-spec.json `
  -ConfigPath .\config\robot.local.psd1 `
  -Force
```

`config\robot.local.psd1` is ignored by Git and should stay local.

## Project Packs

For real work, prefer a project pack outside this public toolchain repo:

```powershell
.\tools\New-FanucProjectPack.ps1 `
  -Path C:\FanucProjects\TestProject `
  -ProjectName TestProject `
  -WorkcellName "Cell 1" `
  -RobotIp 192.0.2.10
```

The project pack creates `config\robot.local.psd1`, `config\cell-map.psd1`,
application specs, generated outputs, evidence, and notes together under the
project folder.

## What Another AI Should Do

Another AI should not infer machine paths from prose. It should:

1. Read `README.md`, `docs\WORKFLOW.md`, and this file.
2. Run `New-FanucRobotConfig.ps1` or `New-FanucProjectPack.ps1`.
3. Ask the human to confirm controller IP, WinOLPC path, RoboGuide path, and
   cell-map policy before live operations.
4. Run `Invoke-FanucToolTests.ps1`.
5. After WinOLPC config is reviewed, run
   `Invoke-FanucToolTests.ps1 -IncludeWinOlpc`.
6. Use explicit `-ConfigPath` for local robot actions.
