# PCDK Strategy

PCDK is a Windows-side FANUC controller interface. In this project it is an evidence and introspection layer, not the primary TP generator.

The core TP workflow remains deterministic:

```text
spec -> reviewed template -> LS -> MakeTP -> PrintTP -> review packet -> simulation -> upload
```

PCDK should surround that workflow with controller state, structured readback, and comparison evidence.

## Local Install

The current workstation has PCDK under:

```text
C:\Program Files (x86)\FANUC\PC Developers Kit
```

Observed local assets:

- `FRRNDev.tlb`
- `Documentation\pcdk.pdf`
- `Documentation\PCDK.chm`
- `Examples\FRRobotDemoCSharp`
- `Examples\AlarmMonitorDotNetCS`

The installed examples exercise the `FRRobot` COM object model for alarms, programs, TP positions, position registers, numeric/string registers, frames, I/O, tasks, current position, features, FTP, and event monitoring.

## Recommended Role

Use PCDK for:

- Controller inventory snapshots.
- Program list and selected-program evidence.
- Alarm/task/current-position evidence.
- Numeric/string register and I/O readback.
- Position register, user frame, and tool frame review.
- RoboGuide vs physical controller comparison.
- Filling or checking real motion application specs before generation.

Keep SNPX first-class for:

- Project-owned runtime signal contracts.
- Compact HMI-style read/write maps.
- Per-project scratch tests and PLC-like integration.

Use FTP/MakeTP/PrintTP for:

- TP file transfer.
- Compile/decode round trips.
- Upload/readback evidence.

## Safety Boundary

The first project-owned PCDK wrapper is read-only by default. It may create a local COM object and inspect the local PCDK installation without contacting a robot. It must not connect to a controller unless the caller explicitly requests `-ConnectReadOnly`.

Blocked in the first PCDK track:

- Program selection or run.
- Task pause, continue, abort, or abort-all.
- I/O writes, simulation, polarity, or configuration changes.
- Frame, tool, position, or position-register update/record/move-to calls.
- Controller clock writes.
- FTP upload/delete.
- Program save/delete.

PCDK can expose these capabilities, which is exactly why the wrapper needs project-owned gates before any write-like behavior is considered.

## Snapshot Contract

The snapshot schema is:

```text
schemas\controller-snapshot.schema.json
```

The read-only snapshot config is:

```text
config\pcdk-snapshot.psd1
```

Generate an offline plan:

```powershell
.\tools\New-FanucPcdkSnapshot.ps1
```

Validate the sample artifact:

```powershell
.\tools\Test-FanucJsonSchema.ps1 -JsonPath .\examples\pcdk\controller-snapshot.plan.json -SchemaPath .\schemas\controller-snapshot.schema.json
```

Live read-only collection, when the robot and network are intentionally in scope:

```powershell
.\tools\New-FanucPcdkSnapshot.ps1 -HostName 192.168.5.10 -ConnectReadOnly
```

The live mode should still record:

- `liveRobotCommandsExecuted=true`
- `controllerWritesExecuted=false`
- `collectionMode=live-read`

## Motion Workflow Use

For real motion applications, PCDK should help verify the resources in the motion application spec:

- UFRAME number, comment, and value.
- UTOOL number, comment, and value.
- Position register values/comments used by the application.
- Current robot position during manual evidence capture.
- Existing program names to prevent accidental production overlap.
- Alarm/task state before and after optional simulation/manual notes.

PCDK evidence can make `ReadyForGeneration` decisions better, but it must not bypass the validator or human review.
