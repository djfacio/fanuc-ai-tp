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
CALL TSKSTATUS('F_FLEXI_LOADER',91,1) ;
```

The no-motion generated caller for controller proof is:

```powershell
.\tools\Invoke-FanucLocalWorkflow.ps1 -SpecPath .\examples\A_TSKTEST.program-spec.json -Force
```

It emits `A_TSKTEST`, whose only executable task-state action is the `CALL`
above, then a completion message.

Arguments:

| Argument | Type | Meaning |
| --- | --- | --- |
| `1` | string | Task/program name to inspect |
| `2` | integer | Base numeric register for the normalized result |
| `3` | integer | Optional display flag; `1` prints raw details, `0` stays quiet |

The base register is caller-owned. For `A_MAIN`, the proposed call uses
`R[91]`. The test caller uses display flag `1`; production orchestration should
use `0` unless an operator-facing diagnostic is intentionally wanted.

## Output Contract

`TSKSTATUS('TASK_NAME',base,display)` writes:

| Register | Meaning |
| --- | --- |
| `R[base]` | Normalized task state |

When `display` is nonzero, KAREL also writes the former debug register details
to user output:

```text
TSKSTATUS <task name>
STATE=<normalized> RAW=<raw TSK_STATUS>
TASK=<task number> LINE=<line number>
KSTAT=<KAREL status>
```

Normalized values:

| Value | Meaning |
| --- | --- |
| `200` | Running |
| `202` | Run request accepted |
| `204` | Inactive / `PG_ABORTED` task instance |
| `404` | Task instance not found; observed as KAREL status `3016` when the program file exists but no active task instance is available |
| `409` | Aborting / conflicting transition |
| `423` | Paused / locked |
| `400` | Missing or invalid `CALL` parameter |
| `502` | `GET_TSK_INFO` failed for another reason |
| `500` | Unrecognized raw task status |

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

Upload the compiled utility without running anything:

```powershell
.\tools\Send-FanucRobotFile.ps1 `
  -LocalPath .\generated\karel\TSKSTATUS.PC `
  -RemoteName TSKSTATUS.PC `
  -Force
```

## A_MAIN Use

Before `A_MAIN` uses `RUN F_FLEXI_LOADER`, it should call:

```ls
CALL TSKSTATUS('F_FLEXI_LOADER',91,0) ;
```

Generated TP must place one compact multi-language `--eg:` remark immediately
before every `CALL TSKSTATUS(...)`. Use `--eg:` instead of `!` because the teach
pendant wraps the remark text. The remark should describe the local decision at
that call site, not just the generic return-code table:

```ls
--eg:TSK 204/404 RUN, ELSE ALARM ;
CALL TSKSTATUS('F_FLEXI_LOADER',91,0) ;
```

Current `A_MAIN` pre-run policy:

- `R[91]=200`: feeder task is already running before `A_MAIN` requested it;
  treat this as an ownership/state violation and alarm.
- `R[91]=423`: do not auto-continue yet; raise a specific state/status path.
- `R[91]=204` or `404`: startable; `RUN F_FLEXI_LOADER`.
- `R[91]=400`, `409`, `500`, or `502`: fail closed and do not start the feeder
  task without a reviewed recovery path.

After `RUN F_FLEXI_LOADER`, `A_MAIN` must recheck and only `R[91]=200` proves
the start request succeeded.

The pendant remark intentionally omits `400`, `500`, and `502` details. Those
are generator/helper fault classifications, not normal human operating choices.

This resolves the design of the single-instance question. `TSKSTATUS.PC` has
now been uploaded and the `R[91]`/display contract has both a live no-instance
proof and a live positive running-task proof.

## Live Proof

On 2026-05-14, the revised `TSKSTATUS.PC` was uploaded and tested through
`A_TSKTEST` against `F_FLEXI_LOADER` while no active task instance existed. The
pendant-visible result was:

```text
STATE=404 RAW=0 TASK=0 LINE=0 KSTAT=3016
```

That proves the observed `GET_TSK_INFO` status `3016` maps cleanly to the
HTTP-like `404` task-instance-not-found result for this helper.

For the positive running-path proof, two no-motion programs were generated,
compiled, uploaded, and read back from the controller on 2026-05-14:

- `A_TSKDUMMY`: displays `DUMMY RUNNING`, waits 30 seconds, then displays
  `DUMMY DONE`.
- `A_TSKRUN`: runs `A_TSKDUMMY`, waits one second, then calls
  `TSKSTATUS('A_TSKDUMMY',91,1)`.

The reviewed `RUN` exception is deliberately narrow: `A_TSKRUN` may only run
`A_TSKDUMMY`, and `A_TSKDUMMY` is motionless. The expected pendant result when
`A_TSKRUN` is run is:

```text
STATE=200 RAW=<controller running code> TASK=<nonzero task> LINE=<line> KSTAT=0
```

The positive proof was run from the pendant on 2026-05-15. The observed result
was:

```text
R[91]=200
STATE=200 RAW=0 TASK=9 LINE=2
```

That proves the normalized `200` running-task result for a known active task.

During first live staging, `A_TSKRUN` could not be overwritten while another
task still owned it, and the first generated copies used
`DEFAULT_GROUP = 1,*,*,*,*;`. The no-motion generator and LS safety gate were
updated so no-motion programs now emit and require:

```ls
DEFAULT_GROUP = *,*,*,*,*,*,*,*;
```

Readback after the corrected upload confirmed that both `A_TSKRUN` and
`A_TSKDUMMY` now use the wildcard default group. The eight-field source form
matches the teach pendant Program Detail Group Mask display and the local
operator manual example in B-83284EN/12 page 550. WinOLPC PrintTP V9.40 may
serialize the compiled wildcard mask back to five fields in decoded LS; the
round-trip gate treats all-wildcard masks as equivalent, but generated source
stays eight-field to match the pendant/manual contract.
