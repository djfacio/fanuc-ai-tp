@{
    SchemaVersion = 1
    Notes = "Read-only observation plan candidates. This map does not grant write permission."

    Transports = @{
        Preferred = @("SNPX", "PCDK", "KAREL_TCP")
        Notes = "Use this map to plan reads first. Implement live reads only after choosing and testing a transport."
    }

    Registers = @(
        @{
            Register = 90
            Name = "AI_REGDIAG marker A"
            Source = "Generated AI diagnostic"
            ExpectedUse = "Confirm AI_REGDIAG ran as reviewed."
        },
        @{
            Register = 91
            Name = "AI_REGDIAG marker B"
            Source = "Generated AI diagnostic"
            ExpectedUse = "Confirm AI_REGDIAG ran as reviewed."
        },
        @{
            Register = 97
            Name = "AI_CELLCHK marker"
            Source = "Generated AI cell preflight"
            ExpectedUse = "Confirm AI_CELLCHK ran as reviewed."
        },
        @{
            Register = 98
            Name = "AI_SNAPSHOT marker"
            Source = "Generated AI snapshot"
            ExpectedUse = "Confirm AI_SNAPSHOT ran as reviewed."
        },
        @{
            Register = 99
            Name = "AI_HELLO marker"
            Source = "Generated AI hello"
            ExpectedUse = "Confirm AI_HELLO ran as reviewed."
        },
        @{
            Register = 103
            Name = "Production sample register"
            Source = "Observed in production analysis"
            ExpectedUse = "Candidate for future read-only mapping review."
        },
        @{
            Register = 107
            Name = "Production sample register"
            Source = "Observed in production analysis"
            ExpectedUse = "Candidate for future read-only mapping review."
        },
        @{
            Register = 110
            Name = "Production sample register"
            Source = "Observed in production analysis"
            ExpectedUse = "Candidate for future read-only mapping review."
        }
    )

    IoSignals = @(
        @{
            Signal = "DO[1]"
            Name = "AI_IODIAG reviewed pulse output"
            Source = "Generated AI diagnostic"
            ExpectedUse = "Confirm reviewed output state before/after AI_IODIAG."
        },
        @{
            Signal = "DO[107]"
            Name = "Production sample output"
            Source = "Observed in BNEMAIN"
            ExpectedUse = "Candidate for future read-only mapping review."
        },
        @{
            Signal = "DO[110]"
            Name = "Production sample output"
            Source = "Observed in ARC3, ARC4, BNEMAIN, F_FEEDER"
            ExpectedUse = "Candidate for future read-only mapping review."
        },
        @{
            Signal = "DO[113]"
            Name = "Production sample output"
            Source = "Observed in BLOWER_TEST, F_FEEDER"
            ExpectedUse = "Candidate for future read-only mapping review."
        }
    )

    ProgramPresence = @(
        @{
            Program = "AI_HELLO"
            Source = "Generated AI baseline"
            ExpectedUse = "Confirm generated program remains present on MD:."
        },
        @{
            Program = "AI_CELLCHK"
            Source = "Generated AI cell preflight"
            ExpectedUse = "Confirm generated program remains present on MD:."
        },
        @{
            Program = "BNEMAIN"
            Source = "Production analysis"
            ExpectedUse = "Candidate orchestration program for future review."
        },
        @{
            Program = "F_FEEDER"
            Source = "Production analysis"
            ExpectedUse = "Candidate IO utility program for future review."
        }
    )

    OperatorChecks = @(
        @{
            Name = "Mode"
            Prompt = "Record controller mode and operator-owned run decision notes."
        },
        @{
            Name = "Override"
            Prompt = "Record override percentage before generated-program verification."
        },
        @{
            Name = "Frames"
            Prompt = "Record active user frame and tool frame assumptions."
        },
        @{
            Name = "Recovery"
            Prompt = "Record safe recovery state before approving new generated behavior."
        }
    )
}
