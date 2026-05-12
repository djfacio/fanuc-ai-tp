@{
    SchemaVersion = 1
    Notes = "Reviewed cell resource map for generated AI_ specs. Keep writes narrow and explicit."

    RegisterWrites = @{
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
