# FANUC Macro TP Programs

Macro programs are normal TP programs stored on `MD:` as `.TP` files. In decoded
LS, PrintTP marks them on the `/PROG` line:

```ls
/PROG  F_OPENG1	  Macro
```

The current evidence does not support `.MR` as a robot file extension for these
programs:

- `dir *.MR` returned no files on the robot.
- Uploading a compiled TP binary as `A_MRTEST.MR` was rejected by robot FTP.
- MakeTP still produced/copied `.TP` output when asked for an `.MR` output path.
- PrintTP did not decode a locally renamed `.MR` binary successfully.

Known macro TP programs in the current robot snapshot:

- `F_BG_SPD_OVRD`
- `F_OPENG1`
- `F_OPENG2`
- `F_PUSHER1`
- `F_PUSHER2`

Generation implication: future macro generation should produce a TP/LS program
whose decoded `/PROG` line contains the `Macro` marker, then compile/upload the
normal `.TP` artifact. Macro button/menu assignment is controller configuration
evidence, not a separate `.MR` file artifact.
