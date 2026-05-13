@{
    SchemaVersion = 1
    Notes = "Optional RoboGuide/manual evidence guidance by generated program risk class."

    EvidenceClasses = @(
        @{
            Name = "no-motion"
            AppliesWhen = "safety.motionAllowed=false and no ioWrite operations"
            RoboguideRequired = $false
            OperatorRunDecisionOwned = $true
            RequiresBeforeAfterSnapshot = $false
            RequiredSections = @("artifact-evidence", "operator-review", "expected-observations", "result")
        },
        @{
            Name = "io-sequence"
            AppliesWhen = "safety.motionAllowed=false and one or more ioWrite operations"
            RoboguideRequired = $false
            OperatorRunDecisionOwned = $true
            RequiresBeforeAfterSnapshot = $false
            RequiredSections = @("artifact-evidence", "io-baseline", "operator-review", "expected-observations", "restore-check", "result")
        },
        @{
            Name = "motion"
            AppliesWhen = "safety.motionAllowed=true"
            RoboguideRequired = $false
            OperatorRunDecisionOwned = $true
            RequiresBeforeAfterSnapshot = $false
            RequiredSections = @("artifact-evidence", "workcell-baseline", "frame-tool-payload", "path-review", "expected-observations", "recovery-plan", "result")
        }
    )
}
