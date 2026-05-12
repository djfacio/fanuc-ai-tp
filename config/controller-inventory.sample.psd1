@{
    SchemaVersion = 1
    InventoryName = "public-sample-r30ib-plus"
    Notes = "Sanitized sample inventory. Copy to config/controller-inventory.local.psd1 for live-cell details; the local file is ignored by Git."

    Controller = @{
        Manufacturer = "FANUC"
        Family = "R-30iB Plus"
        SoftwareVersion = "V9.x"
        RobotModel = "Example robot"
        HasAsciiUpload = $false
        HasKarel = $false
        HasPcdk = $false
        HasSnpx = $false
    }

    Connectivity = @{
        Ftp = @{
            Enabled = $false
            Host = "192.0.2.10"
            Port = 21
            UserName = "anonymous"
            PasswordMode = "controller-default-or-local-secret"
        }
        Snpx = @{
            Enabled = $false
            Host = "192.0.2.10"
            Protocol = "SNPX_V2"
            Port = 60008
            MappingMode = "per-connection"
        }
        KarelTcp = @{
            Enabled = $false
            Port = $null
            MessageFormat = "undecided"
        }
        Pcdk = @{
            Enabled = $false
        }
    }

    LocalTools = @{
        WinOlpc = @{
            Available = $false
            Version = ""
            MakeTpPath = ""
            PrintTpPath = ""
        }
        RoboGuide = @{
            Available = $false
            WorkcellRobotPath = ""
        }
        VsCodeExtensions = @(
            "KAREL",
            "Python",
            "Panel"
        )
    }

    WorkflowPolicy = @{
        AllowCompileTp = $false
        AllowFtpUpload = $false
        AllowTpReadback = $false
        AllowSnpxRead = $false
        AllowSnpxWrite = $false
        AllowKarelBridge = $false
        AllowRoboguideEvidence = $false
        RequiresHumanApproval = $true
    }
}
