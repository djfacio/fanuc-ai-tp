@{
    SchemaVersion = 1
    Notes = "Deterministic FANUC TP template catalog. Templates are spec-driven and no-motion unless explicitly reviewed otherwise."

    Templates = @(
        @{
            Id = "hello-marker"
            ProgramName = "AI_HELLO"
            ExampleSpec = "examples\AI_HELLO.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Display an operator message and write one marker register."
            AllowedOperationTypes = @("message", "registerWrite")
            RegisterWrites = @("R[99]")
            IoWrites = @()
            CallTargets = @()
            Evidence = @("schema-validation", "cell-map-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "manual-t1")
            Status = "proven-live"
        },
        @{
            Id = "register-diagnostic"
            ProgramName = "AI_REGDIAG"
            ExampleSpec = "examples\AI_REGDIAG.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Write reviewed marker registers for diagnostic confirmation."
            AllowedOperationTypes = @("message", "registerWrite")
            RegisterWrites = @("R[90]", "R[91]")
            IoWrites = @()
            CallTargets = @()
            Evidence = @("schema-validation", "cell-map-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "manual-t1")
            Status = "proven-live"
        },
        @{
            Id = "io-pulse-diagnostic"
            ProgramName = "AI_IODIAG"
            ExampleSpec = "examples\AI_IODIAG.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Pulse a reviewed output with an explicit restore to OFF."
            AllowedOperationTypes = @("message", "ioWrite", "wait")
            RegisterWrites = @()
            IoWrites = @("DO[1]")
            CallTargets = @()
            Evidence = @("schema-validation", "cell-map-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "roboguide-or-controlled-live", "manual-t1")
            Status = "proven-live"
        },
        @{
            Id = "position-register-checklist"
            ProgramName = "AI_PRCHECK"
            ExampleSpec = "examples\AI_PRCHECK.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Display a pendant checklist for position register review without modifying PR data."
            AllowedOperationTypes = @("message", "comment")
            RegisterWrites = @()
            IoWrites = @()
            CallTargets = @()
            Evidence = @("schema-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "manual-t1")
            Status = "proven-live"
        },
        @{
            Id = "frame-tool-checklist"
            ProgramName = "AI_FRMTOOL"
            ExampleSpec = "examples\AI_FRMTOOL.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Display a pendant checklist for frame and tool review without editing UFRAME or UTOOL."
            AllowedOperationTypes = @("message", "comment")
            RegisterWrites = @()
            IoWrites = @()
            CallTargets = @()
            Evidence = @("schema-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "manual-t1")
            Status = "proven-live"
        },
        @{
            Id = "state-snapshot-checklist"
            ProgramName = "AI_SNAPSHOT"
            ExampleSpec = "examples\AI_SNAPSHOT.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Write a snapshot marker and display operator-guided state checks."
            AllowedOperationTypes = @("message", "registerWrite", "diagnosticCheck")
            RegisterWrites = @("R[98]")
            IoWrites = @()
            CallTargets = @()
            Evidence = @("schema-validation", "cell-map-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "manual-t1")
            Status = "proven-live"
        },
        @{
            Id = "cell-preflight-checklist"
            ProgramName = "AI_CELLCHK"
            ExampleSpec = "examples\AI_CELLCHK.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Write a cell-check marker and display a preflight checklist."
            AllowedOperationTypes = @("message", "registerWrite", "diagnosticCheck")
            RegisterWrites = @("R[97]")
            IoWrites = @()
            CallTargets = @()
            Evidence = @("schema-validation", "cell-map-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "manual-t1")
            Status = "proven-live"
        }
    )
}
