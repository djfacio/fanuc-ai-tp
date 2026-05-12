@{
    SchemaVersion = 1
    PolicyScope = "local-commissioning-test"
    ProjectName = "fanuc-ai-tp local commissioning"
    WorkcellName = "TA_Aerospace Robot_1 test cell"
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
                Notes = "Reviewed no-motion cell checklist marker."
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
        Allowed = @()
        Notes = "No generated CALL targets are approved yet. Add entries only after review."
    }
}
