# KAREL Task State Helper

This is the narrow KAREL path for checking whether an async/background task is
already running before `A_MAIN` starts or depends on it.

It is not the KAREL TCP bridge. It does not start, pause, abort, resume, select,
or move programs. It reads task state and writes status evidence to reviewed
registers.

## Local Manual Basis

Local manual `b-83144en-1-02` supports this design:

- Page 165: KAREL task control and monitoring includes `GET_TSK_INFO`; it can
  determine whether a task is running, paused, or aborted, and report program,
  line number, and wait state.
- Pages 264-265: `GET_TSK_INFO(task_name, task_no, attribute, value_int,
  value_str, status)` supports `TSK_STATUS`, `TSK_LINENUM`, `TSK_PROGNAME`, and
  status values such as `PG_RUNNING`, `PG_PAUSED`, and `PG_ABORTED`.
- Page 342: `SET_INT_REG(register_no, int_value, status)` stores integer values
  in numeric registers.

Translator note: the manual names the built-in group `PBCORE`. Local WinOLPC
KTRANS V9.40 loads that core environment by default, so generated source does
not declare it explicitly; it declares only `%ENVIRONMENT REGOPE` for register
writes.

## Tooling

Generate the KAREL source:

```powershell
.\tools\New-FanucTaskStateKarelSource.ps1 `
  -ProgramName A_TSKSTAT `
  -TargetTask F_FLEXI_LOADER `
  -OutputPath .\prototypes\karel\A_TSKSTAT.KL `
  -Force
```

Current generated source:

```text
prototypes\karel\A_TSKSTAT.KL
```

Compile locally with WinOLPC KTRANS:

```powershell
.\tools\Invoke-FanucKarelBuild.ps1 `
  -SourcePath .\prototypes\karel\A_TSKSTAT.KL `
  -Force
```

The build writes:

```text
generated\karel\A_TSKSTAT.PC
generated\karel\A_TSKSTAT.LS
```

## Output Contract

`A_TSKSTAT` checks `F_FLEXI_LOADER` and writes:

| Register | Meaning |
| --- | --- |
| `R[91]` | Normalized task state |
| `R[92]` | Raw `TSK_STATUS` value from `GET_TSK_INFO` |
| `R[93]` | Task number returned by `GET_TSK_INFO` |
| `R[94]` | Current executing line number, or `0` if unavailable |
| `R[95]` | KAREL `status` from the first `GET_TSK_INFO` call |

Normalized `R[91]` values:

| Value | Meaning |
| --- | --- |
| `10` | Run request accepted |
| `20` | Running |
| `30` | Paused |
| `40` | Aborted or not running |
| `50` | Aborting |
| `900` | `GET_TSK_INFO` failed |
| `999` | Unrecognized raw task status |

## A_MAIN Use

Before `A_MAIN` uses `RUN F_FLEXI_LOADER`, it should call `A_TSKSTAT` and branch
on `R[91]`.

Recommended first policy:

- `R[91]=20`: feeder task is already running; do not issue another `RUN`.
- `R[91]=10`: treat as in transition; wait briefly, recheck, then decide.
- `R[91]=30`: do not auto-continue yet; raise a specific state/status path.
- `R[91]=40`: safe candidate to `RUN`, subject to the rest of the startup
  preconditions.
- `R[91]=900` or `999`: fail closed and do not start the feeder task.

This resolves the single-instance question only after the KAREL source compiles,
is uploaded, and the register contract is tested on the controller.
