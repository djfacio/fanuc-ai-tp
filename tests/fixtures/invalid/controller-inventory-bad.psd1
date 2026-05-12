@{
    SchemaVersion = 1
    InventoryName = "bad-inventory"

    Controller = @{
        Manufacturer = "FANUC"
        Family = "R-30iB Plus"
        SoftwareVersion = "V9.x"
    }

    Connectivity = @{
        Ftp = @{
            Enabled = $false
            Host = "192.0.2.10"
            Port = 21
        }
        Snpx = @{
            Enabled = $false
            Host = "192.0.2.10"
            Protocol = "SNPX_V2"
            Port = 60008
            MappingMode = "per-connection"
        }
    }

    LocalTools = @{
        WinOlpc = @{
            Available = $false
            MakeTpPath = ""
        }
        RoboGuide = @{
            Available = $false
            WorkcellRobotPath = ""
        }
    }

    WorkflowPolicy = @{
        AllowCompileTp = $true
        AllowFtpUpload = $true
        AllowTpReadback = $false
        AllowSnpxRead = $false
        AllowSnpxWrite = $true
        AllowKarelBridge = $false
        AllowRoboguideEvidence = $false
        RequiresHumanApproval = $false
    }
}
