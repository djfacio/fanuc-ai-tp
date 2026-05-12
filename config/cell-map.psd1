@{
    SchemaVersion = 1
    Notes = "Reviewed cell resource map for generated AI_ specs. User-approved writable scratch scope is R[90]-R[99] and DO[1]-DO[80]. Production/status values outside that scope are read-only unless separately approved."

    RegisterWrites = @{
        AllowedRanges = @(
            @{
                Start = 90
                End = 99
                Name = "AI scratch marker registers"
                Notes = "User-approved scratch register range. Do not write production/status registers outside this range."
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
                Name = "AI scratch digital outputs"
                SafeStates = @("ON", "OFF")
                Notes = "User-approved scratch output range. Outputs above DO[80] remain read-only unless separately approved."
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
