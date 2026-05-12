@{
    SchemaVersion = 1
    Notes = "Project interface strategy. Generated workflows should choose the narrowest interface that satisfies the task."

    Interfaces = @(
        @{
            Name = "ftp-tp-artifact"
            Enabled = $true
            Role = "Transfer compiled TP artifacts and read back robot files."
            Direction = "pc-to-controller-files"
            CommandAuthority = "file-transfer-only"
            AllowsProgramRun = $false
            AllowsRobotMotion = $false
            AllowsLiveWrites = $false
            SafetyGates = @("AI-prefix", "ls-safety", "manifest-readyForUpload", "human-review", "readback-hash")
        },
        @{
            Name = "snpx-v2"
            Enabled = $true
            Role = "Read/write reviewed status markers and simple mapped IO through private per-connection ASG."
            Direction = "pc-to-controller-memory"
            CommandAuthority = "allowlisted-memory"
            AllowsProgramRun = $false
            AllowsRobotMotion = $false
            AllowsLiveWrites = $true
            SafetyGates = @("cell-map", "snpx-write-plan", "exact-approval-phrase", "pre-read", "post-read", "restore-when-required")
        },
        @{
            Name = "karel-tcp-bridge"
            Enabled = $false
            Role = "Future robot-resident JSON bridge for richer status snapshots and tightly scoped commands."
            Direction = "bidirectional-messages"
            CommandAuthority = "proposed-reviewed-messages"
            AllowsProgramRun = $false
            AllowsRobotMotion = $false
            AllowsLiveWrites = $false
            MessageFormat = "newline-delimited-json"
            SafetyGates = @("message-schema", "command-allowlist", "sequence-id", "operator-approval", "audit-log", "rollback-plan")
        },
        @{
            Name = "pcdk"
            Enabled = $false
            Role = "Future PC-side automation option for controller introspection and tooling integration."
            Direction = "pc-api"
            CommandAuthority = "proposed-read-mostly"
            AllowsProgramRun = $false
            AllowsRobotMotion = $false
            AllowsLiveWrites = $false
            SafetyGates = @("capability-inventory", "read-only-default", "operator-approval")
        },
        @{
            Name = "roboguide"
            Enabled = $true
            Role = "Simulation and evidence environment before physical-cell execution."
            Direction = "simulation"
            CommandAuthority = "virtual-controller-only"
            AllowsProgramRun = $true
            AllowsRobotMotion = $true
            AllowsLiveWrites = $false
            SafetyGates = @("evidence-packet", "workcell-review", "manual-result-record")
        }
    )

    MessageSchemas = @(
        @{
            Name = "status.snapshot.request"
            Interface = "karel-tcp-bridge"
            Direction = "pc-to-robot"
            Enabled = $false
            RequiredFields = @("schemaVersion", "messageType", "requestId")
            AllowsWrites = $false
        },
        @{
            Name = "status.snapshot.response"
            Interface = "karel-tcp-bridge"
            Direction = "robot-to-pc"
            Enabled = $false
            RequiredFields = @("schemaVersion", "messageType", "requestId", "status", "values")
            AllowsWrites = $false
        },
        @{
            Name = "command.reviewed-write.request"
            Interface = "karel-tcp-bridge"
            Direction = "pc-to-robot"
            Enabled = $false
            RequiredFields = @("schemaVersion", "messageType", "requestId", "target", "value", "approvalPhrase")
            AllowsWrites = $true
        },
        @{
            Name = "command.reviewed-write.response"
            Interface = "karel-tcp-bridge"
            Direction = "robot-to-pc"
            Enabled = $false
            RequiredFields = @("schemaVersion", "messageType", "requestId", "status", "before", "after")
            AllowsWrites = $false
        }
    )
}
