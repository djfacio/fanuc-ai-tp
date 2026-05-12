@{
    SchemaVersion = 1
    Notes = "RoboGuide/manual evidence policy by generated program risk class."

    EvidenceClasses = @(
        @{
            Name = "no-motion"
            AppliesWhen = "safety.motionAllowed=false and no ioWrite operations"
            RoboguideRequired = $false
            ManualT1Required = $true
            RequiresBeforeAfterSnapshot = $false
            RequiredSections = @("artifact-evidence", "operator-review", "expected-observations", "result")
        },
        @{
            Name = "io-sequence"
            AppliesWhen = "safety.motionAllowed=false and one or more ioWrite operations"
            RoboguideRequired = $true
            ManualT1Required = $true
            RequiresBeforeAfterSnapshot = $true
            RequiredSections = @("artifact-evidence", "io-baseline", "operator-review", "expected-observations", "restore-check", "result")
        },
        @{
            Name = "motion"
            AppliesWhen = "safety.motionAllowed=true"
            RoboguideRequired = $true
            ManualT1Required = $true
            RequiresBeforeAfterSnapshot = $true
            RequiredSections = @("artifact-evidence", "workcell-baseline", "frame-tool-payload", "path-review", "expected-observations", "recovery-plan", "result")
        }
    )
}
