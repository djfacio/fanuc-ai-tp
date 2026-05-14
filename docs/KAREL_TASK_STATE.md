# KAREL Task State Helper

`TSKSTATUS` is the narrow KAREL utility for checking whether an async/background
task is already running before `A_MAIN` starts or depends on it.

It is not the KAREL TCP bridge. It does not start, pause, abort, resume, select,
or move programs. It reads task state and writes status evidence to caller-chosen
registers.

`TSKSTATUS` is a reviewed exception to the generated `A_` prefix because it is a
general utility, not an application workflow program.

## Local Manual Basis

Local manual `b-83144en-1-02` supports this design:

- Page 165: KAREL task control and monitoring includes `GET_TSK_INFO`; it can
  determine whether a task is running, paused, or aborted, and report program,
  line number, and wait state.
- Pages 264-265: `GET_TSK_INFO(task_name, task_no, attribute, value_int,
  value_str, status)` supports `TSK_STATUS`, `TSK_LINENUM`, `TSK_PROGNAME`, and
  status values such as `PG_RUNNING`, `PG_PAUSED`, and `PG_ABORTED`.
- Page 262: TP `CALL` parameters can be read from KAREL using `GET_TPE_PRM`.
- Page 342: `SET_INT_REG(register_no, int_value, status)` stores integer values
  in numeric registers.

Translator note: the manual names the built-in group `PBCORE`. Local WinOLPC
KTRANS V9.40 loads that core environment by default, so generated source does
not declare it explicitly; it declares only `%ENVIRONMENT REGOPE` for register
writes.

## Call Interface

From TP:

```ls
CALL TSKSTATUS('F_FLEXI_LOADER',91) ;
```

Arguments:

| Argument | Type | Meaning |
| --- | --- | --- |
| `1` | string | Task/program name to inspect |
| `2` | integer | Base numeric register for the result block |

The base register is caller-owned. For `A_MAIN`, the proposed call uses base
`R[91]`.

## Output Contract

`TSKSTATUS('TASK_NAME',base)` writes:

| Register | Meaning |
| --- | --- |
| `R[base]` | Normalized task state |
| `R[base+1]` | Raw `TSK_STATUS` value from `GET_TSK_INFO` |
| `R[base+2]` | Task number returned by `GET_TSK_INFO` |
| `R[base+3]` | Current executing line number, or `0` if unavailable |
| `R[base+4]` | KAREL `status` from first `GET_TSK_INFO` or parameter read |

Normalized values:

| Value | Meaning |
| --- | --- |
| `10` | Run request accepted |
| `20` | Running |
| `30` | Paused |
| `40` | Aborted or not running |
| `50` | Aborting |
| `901` | Missing or invalid `CALL` parameter |
| `900` | `GET_TSK_INFO` failed |
| `999` | Unrecognized raw task status |

## Tooling

Generate the KAREL source:

```powershell
.\tools\New-FanucTaskStateKarelSource.ps1 `
  -ProgramName TSKSTATUS `
  -OutputPath .\prototypes\karel\TSKSTATUS.KL `
  -Force
```

Compile locally with WinOLPC KTRANS:

```powershell
.\tools\Invoke-FanucKarelBuild.ps1 `
  -SourcePath .\prototypes\karel\TSKSTATUS.KL `
  -Force
```

The build writes generated artifacts:

```text
generated\karel\TSKSTATUS.PC
generated\karel\TSKSTATUS.LS
```

## A_MAIN Use

Before `A_MAIN` uses `RUN F_FLEXI_LOADER`, it should call:

```ls
CALL TSKSTATUS('F_FLEXI_LOADER',91) ;
```

Recommended first policy:

- `R[91]=20`: feeder task is already running; do not issue another `RUN`.
- `R[91]=10`: treat as in transition; wait briefly, recheck, then decide.
- `R[91]=30`: do not auto-continue yet; raise a specific state/status path.
- `R[91]=40`: safe candidate to `RUN`, subject to the rest of the startup
  preconditions.
- `R[91]=900`, `901`, or `999`: fail closed and do not start the feeder task.

This resolves the design of the single-instance question. It does not clear the
gate until `TSKSTATUS.PC` is uploaded and the register contract is tested on the
controller.
