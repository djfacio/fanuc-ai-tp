@{
    SchemaVersion = 1
    PolicyScope = "project-template"
    ProjectName = "REVIEW_AND_RENAME"
    WorkcellName = "REVIEW_AND_RENAME"
    Notes = "Safe starter cell resource map. Copy to config\cell-map.psd1 for a project/workcell and review every range before enabling live writes."

    RegisterWrites = @{
        AllowedRanges = @()
        Allowed = @()
    }

    IoWrites = @{
        AllowedRanges = @()
        Allowed = @()
    }

    Calls = @{
        Allowed = @()
        Notes = "No generated CALL targets are approved in the starter policy."
    }
}
