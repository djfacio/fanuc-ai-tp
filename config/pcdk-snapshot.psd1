@{
    SchemaVersion = 1
    Notes = "Read-only PCDK controller snapshot plan. This config grants no controller writes, program runs, task control, or motion authority."

    Pcdk = @{
        Required = $false
        InstallRoot = "C:\Program Files (x86)\FANUC\PC Developers Kit"
        ComProgId = "FRRobot.FRCRobot"
        TypeLibrary = "FRRNDev.tlb"
        Documentation = "Documentation\pcdk.pdf"
        ExampleRoot = "Examples\FRRobotDemoCSharp"
    }

    Defaults = @{
        ConnectReadOnly = $false
        MaxPrograms = 200
        MaxAlarms = 50
        MaxNumericRegisters = 120
        MaxStringRegisters = 50
        MaxPositionRegisters = 100
        MaxFrames = 20
        MaxIoSignalsPerType = 120
        ConnectionTimeoutSeconds = 15
    }

    SnapshotSections = @(
        @{
            Name = "pcdk-install"
            Enabled = $true
            ReadOnly = $true
            Description = "Local PCDK install, documentation, type library, and example availability."
        },
        @{
            Name = "controller-identity"
            Enabled = $true
            ReadOnly = $true
            Description = "Host, connection state, application/version/controller identifiers, and memory summary when available."
        },
        @{
            Name = "programs"
            Enabled = $true
            ReadOnly = $true
            Description = "Program names, selected program, attributes, and TP/KAREL/VR type hints."
        },
        @{
            Name = "tasks"
            Enabled = $true
            ReadOnly = $true
            Description = "Task names and task states for evidence. No pause, continue, abort, or run calls."
        },
        @{
            Name = "alarms"
            Enabled = $true
            ReadOnly = $true
            Description = "Active alarm summary and alarm text."
        },
        @{
            Name = "registers"
            Enabled = $true
            ReadOnly = $true
            Description = "Numeric and string register values/comments for application evidence."
        },
        @{
            Name = "position-registers"
            Enabled = $true
            ReadOnly = $true
            Description = "Position register initialization, comments, group data, user frame, user tool, and position values when available."
        },
        @{
            Name = "frames"
            Enabled = $true
            ReadOnly = $true
            Description = "User/tool frame comments and values for motion application verification."
        },
        @{
            Name = "current-position"
            Enabled = $true
            ReadOnly = $true
            Description = "Current robot position and active frame/tool context when available."
        },
        @{
            Name = "io"
            Enabled = $true
            ReadOnly = $true
            Description = "I/O values and comments for evidence. No signal writes, simulation, inversion, or configuration."
        },
        @{
            Name = "features"
            Enabled = $true
            ReadOnly = $true
            Description = "Installed FANUC features/options where the controller exposes them."
        }
    )

    BlockedPcdkCapabilities = @(
        "Programs.Selected",
        "Task.Abort",
        "Tasks.AbortAll",
        "Task.Pause",
        "Tasks.PauseAll",
        "Task.Continue",
        "I/O.Value write",
        "I/O.Config write",
        "I/O.Simulate write",
        "SysInfo.Clock write",
        "Frame.Update",
        "Position.Record",
        "Position.Update",
        "Position.MoveTo",
        "FTP.PutFile",
        "FTP.Delete",
        "Program.Save",
        "Program.Delete"
    )
}
