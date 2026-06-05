@{
    SchemaVersion = 1
    PolicyScope = "local-commissioning-test"
    ProjectName = "fanuc-ai-tp local commissioning"
    WorkcellName = "Sample FANUC test cell"
    Notes = "Reviewed cell resource map for this local commissioning/test project. The temporary writable scratch scope is R[90]-R[99] and DO[1]-DO[80]. Establish a separate map for each project/workcell."

    RegisterWrites = @{
        AllowedRanges = @(
            @{
                Start = 90
                End = 99
                Name = "Local test scratch marker registers"
                Notes = "Temporary scratch register range for this commissioning/test project. Do not carry this range into another project without review."
            }
        )
        Allowed = @(
            @{
                Register = 90
                Name = "AI_REGDIAG marker A"
                Notes = "Reviewed no-motion diagnostic marker."
            },
            @{
                Register = 91
                Name = "AI_REGDIAG marker B"
                Notes = "Reviewed no-motion diagnostic marker."
            },
            @{
                Register = 97
                Name = "AI_CELLCHK marker"
                Notes = "Reviewed no-motion cell preflight marker."
            },
            @{
                Register = 98
                Name = "AI_SNAPSHOT marker"
                Notes = "Reviewed no-motion snapshot marker."
            },
            @{
                Register = 99
                Name = "AI_HELLO marker"
                Notes = "Reviewed no-motion hello marker."
            }
        )
    }

    IoWrites = @{
        AllowedRanges = @(
            @{
                Type = "DO"
                Start = 1
                End = 80
                Name = "Local test scratch digital outputs"
                SafeStates = @("ON", "OFF")
                Notes = "Temporary scratch output range for this commissioning/test project. Do not carry this range into another project without review."
            }
        )
        Allowed = @(
            @{
                Signal = "DO[1]"
                Name = "Reviewed AI_IODIAG pulse output"
                SafeStates = @("ON", "OFF")
                Notes = "User reviewed and approved this output for AI_IODIAG testing."
            }
        )
    }

    Calls = @{
        Allowed = @(
            @{
                Program = "TSKSTATUS"
                MotionAllowed = $false
                Notes = "Reviewed task-status utility. Does not run, pause, abort, resume, select, or move programs."
                Arguments = @(
                    @{
                        Position = 1
                        Type = "string"
                        AllowedValues = @("F_FLEXI_LOADER", "A_FLEXI_LOADER", "A_CONVEYOR", "A_MAIN", "A_TSKDUMMY")
                        Notes = "Task/program names currently approved for async task ownership checks."
                    },
                    @{
                        Position = 2
                        Type = "integer"
                        Min = 91
                        Max = 93
                        RegisterWriteBlockLength = 1
                        Notes = "TSKSTATUS writes only R[base]. Current generated A_ workflow uses R[91] in A_MAIN, R[92] in A_FLEXI_LOADER, and R[93] in A_PLACE_CONVEYOR to avoid async task races."
                    },
                    @{
                        Position = 3
                        Type = "integer"
                        Min = 0
                        Max = 1
                        Required = $false
                        Notes = "Optional display flag. 1 prints raw task details to the KAREL user output instead of using R[92]-R[95]."
                    }
                )
            },
            @{
                Program = "A_REGCMT"
                MotionAllowed = $false
                Notes = "Reviewed register-comment utility. Uses SET_REG_CMT only for R[80] and R[90]-R[94]; it does not write register values, IO, motion, task control, or program selection."
                Arguments = @()
            },
            @{
                Program = "A_CALC_POS"
                MotionAllowed = $true
                Notes = "Reviewed calculated-PR utility name for motion-action programs. It may be called by generated motion templates when a spec grants the call. It is expected to use Group 1, perform PR math only, and avoid IO, task control, system variables, program selection, and motion lines. PR writes still require per-family/per-program confirmation before generation."
                Arguments = @()
            }
        )
        Notes = "Generated CALL targets must be explicitly reviewed. TSKSTATUS is allowed only for the listed argument contract. A_CALC_POS is a motion-affecting PR calculation boundary, not a no-motion utility."
    }

    Runs = @{
        Allowed = @(
            @{
                Program = "A_TSKDUMMY"
                MotionAllowed = $false
                Notes = "No-motion task-status positive-path proof target. It only waits long enough to be observed by TSKSTATUS."
            },
            @{
                Program = "F_FLEXI_LOADER"
                MotionAllowed = $false
                Notes = "Async feeder/vision task may be started by generated A_MAIN only after TSKSTATUS reports 204 or 404 before the start request. If the task is already running or reports any other state before RUN, A_MAIN must fault/hold. After RUN, TSKSTATUS must report 200 or A_MAIN must fault/hold."
            },
            @{
                Program = "A_FLEXI_LOADER"
                MotionAllowed = $false
                Notes = "Migrated async feeder/vision task. A_MAIN may start it only after TSKSTATUS reports 204 or 404 before RUN, and must verify 200 after RUN or accept a fast-complete Part_Ready state."
            },
            @{
                Program = "A_CONVEYOR"
                MotionAllowed = $false
                Notes = "Migrated conveyor async task started by A_PLACE_CONVEYOR. It owns conveyor flag/output behavior and must remain guarded by A_CONV_DROP/A_PLACE_CONVEYOR stop policy."
            }
        )
        Notes = "Generated RUN targets must be explicitly reviewed and no-motion unless a separate async-task contract is approved."
    }
}
