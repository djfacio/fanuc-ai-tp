@{
    SchemaVersion = 1
    Enabled = $false
    Protocol = "SNPX_V2"
    MappingMode = "per-connection"
    MappingSource = "config\snpx-readonly.psd1"
    CellMapSource = "config\cell-map.psd1"
    DefaultMode = "plan"
    RequireHumanApproval = $true
    Notes = "SNPX writes are supported as a separate allowlisted command path. User-approved scratch boundary is R[90]-R[99] and DO[1]-DO[80], but live SNPX writes still require explicit entries here and matching ASG mappings. Status snapshots remain read-only."

    AllowedWrites = @(
        @{
            Name = "AI_REGDIAG marker A"
            Fanuc = "R[90]"
            Type = "int"
            Transport = "asg-projection"
            SnpxAddress = "%R00005"
            WordCount = 2
            Min = -999999
            Max = 999999
            RequiresCellMap = $true
            Notes = "Approved diagnostic marker register."
        },
        @{
            Name = "AI_REGDIAG marker B"
            Fanuc = "R[91]"
            Type = "int"
            Transport = "asg-projection"
            SnpxAddress = "%R00007"
            WordCount = 2
            Min = -999999
            Max = 999999
            RequiresCellMap = $true
            Notes = "Approved diagnostic marker register."
        },
        @{
            Name = "AI_CELLCHK marker"
            Fanuc = "R[97]"
            Type = "int"
            Transport = "asg-projection"
            SnpxAddress = "%R00009"
            WordCount = 2
            Min = -999999
            Max = 999999
            RequiresCellMap = $true
            Notes = "Approved cell-check marker register."
        },
        @{
            Name = "AI_SNAPSHOT marker"
            Fanuc = "R[98]"
            Type = "int"
            Transport = "asg-projection"
            SnpxAddress = "%R00011"
            WordCount = 2
            Min = -999999
            Max = 999999
            RequiresCellMap = $true
            Notes = "Approved snapshot marker register."
        },
        @{
            Name = "AI_HELLO marker"
            Fanuc = "R[99]"
            Type = "int"
            Transport = "asg-projection"
            SnpxAddress = "%R00013"
            WordCount = 2
            Min = -999999
            Max = 999999
            RequiresCellMap = $true
            Notes = "Approved hello marker register."
        },
        @{
            Name = "AI_IODIAG reviewed pulse output"
            Fanuc = "DO[1]"
            Type = "bool"
            Transport = "asg-projection"
            SnpxAddress = "%R00015"
            WordCount = 2
            AllowedStates = @("ON", "OFF")
            RequiresCellMap = $true
            RequiresLiveProof = $true
            Notes = "Output writes that request ON must restore to OFF and record post-restore readback evidence."
        }
    )

    BlockedClasses = @(
        "SystemVariables",
        "UOP",
        "SOP",
        "DCS",
        "MotionState",
        "ProductionProgramState",
        "UnmappedRegisters",
        "UnmappedIO"
    )
}
