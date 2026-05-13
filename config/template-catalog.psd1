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
            Evidence = @("schema-validation", "cell-map-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "operator-owned-run-decision")
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
            Evidence = @("schema-validation", "cell-map-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "operator-owned-run-decision")
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
            Evidence = @("schema-validation", "cell-map-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "roboguide-or-controlled-live", "operator-owned-run-decision")
            Status = "proven-live"
        },
        @{
            Id = "position-register-review"
            ProgramName = "AI_PRCHECK"
            ExampleSpec = "examples\AI_PRCHECK.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Display position register review notes without modifying PR data."
            AllowedOperationTypes = @("message", "comment")
            RegisterWrites = @()
            IoWrites = @()
            CallTargets = @()
            Evidence = @("schema-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "operator-owned-run-decision")
            Status = "proven-live"
        },
        @{
            Id = "frame-tool-review"
            ProgramName = "AI_FRMTOOL"
            ExampleSpec = "examples\AI_FRMTOOL.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Display frame and tool review notes without editing UFRAME or UTOOL."
            AllowedOperationTypes = @("message", "comment")
            RegisterWrites = @()
            IoWrites = @()
            CallTargets = @()
            Evidence = @("schema-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "operator-owned-run-decision")
            Status = "proven-live"
        },
        @{
            Id = "state-snapshot-review"
            ProgramName = "AI_SNAPSHOT"
            ExampleSpec = "examples\AI_SNAPSHOT.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Write a snapshot marker and display operator-guided state checks."
            AllowedOperationTypes = @("message", "registerWrite", "diagnosticCheck")
            RegisterWrites = @("R[98]")
            IoWrites = @()
            CallTargets = @()
            Evidence = @("schema-validation", "cell-map-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "operator-owned-run-decision")
            Status = "proven-live"
        },
        @{
            Id = "cell-preflight-review"
            ProgramName = "AI_CELLCHK"
            ExampleSpec = "examples\AI_CELLCHK.program-spec.json"
            MotionClass = "no-motion"
            Purpose = "Write a cell-check marker and display preflight review notes."
            AllowedOperationTypes = @("message", "registerWrite", "diagnosticCheck")
            RegisterWrites = @("R[97]")
            IoWrites = @()
            CallTargets = @()
            Evidence = @("schema-validation", "cell-map-validation", "ls-safety", "maketp", "printtp-roundtrip", "human-review", "operator-owned-run-decision")
            Status = "proven-live"
        },
        @{
            Id = "pr-waypoint-sequence-v1"
            ProgramName = "AI_MOTION_PR_READY"
            SpecType = "motion-application"
            TemplateId = "pr-waypoint-sequence-v1"
            ExampleSpec = "tests\fixtures\valid\AI_MOTION_PR_READY.motion-application.json"
            MotionClass = "motion-reviewed"
            Purpose = "Emit a reviewed PR waypoint motion sequence with reviewed UFRAME, UTOOL, and payload schedule."
            AllowedOperationTypes = @("setUserFrame", "setUserTool", "setPayload", "motionPrWaypoint")
            RegisterWrites = @()
            IoWrites = @()
            CallTargets = @()
            PositionRegisters = @("PR[90]", "PR[91]", "PR[92]")
            Evidence = @("motion-application-validation", "motion-ls-spec-match", "ls-safety", "maketp", "printtp-roundtrip", "optional-roboguide-evidence", "operator-owned-robot-setup")
            Status = "offline-validated"
        },
        @{
            Id = "approach-process-retract-v1"
            ProgramName = "AI_APR_PATH"
            SpecType = "motion-application"
            TemplateId = "approach-process-retract-v1"
            ExampleSpec = "examples\applications\AI_APR_PATH.motion-application.json"
            MotionClass = "motion-reviewed"
            Purpose = "Emit a reviewed approach, process, and retract PR waypoint sequence."
            AllowedOperationTypes = @("setUserFrame", "setUserTool", "setPayload", "motionPrWaypoint")
            RegisterWrites = @()
            IoWrites = @()
            CallTargets = @()
            PositionRegisters = @("PR[303]", "PR[304]", "PR[305]")
            Evidence = @("motion-application-validation", "motion-ls-spec-match", "ls-safety", "maketp", "printtp-roundtrip", "optional-roboguide-evidence", "operator-owned-robot-setup")
            Status = "offline-validated"
        },
        @{
            Id = "io-motion-sequence-v1"
            ProgramName = "AI_IOPATH"
            SpecType = "motion-application"
            TemplateId = "io-motion-sequence-v1"
            ExampleSpec = "examples\applications\AI_IOPATH.motion-application.json"
            MotionClass = "motion-reviewed"
            Purpose = "Emit reviewed PR waypoint motion with allowlisted digital output actions."
            AllowedOperationTypes = @("setUserFrame", "setUserTool", "setPayload", "motionPrWaypoint", "ioWrite")
            RegisterWrites = @()
            IoWrites = @("DO[2]")
            CallTargets = @()
            PositionRegisters = @("PR[306]", "PR[307]", "PR[308]")
            Evidence = @("motion-application-validation", "motion-ls-spec-match", "ls-safety", "maketp", "printtp-roundtrip", "optional-roboguide-evidence", "operator-owned-robot-setup")
            Status = "offline-validated"
        }
    )
}
