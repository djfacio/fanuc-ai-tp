@{
    SchemaVersion = 1
    ProjectName = "SampleProject"
    WorkcellName = "SampleCell"
    PolicyScope = "sample-no-live-writes"
    Notes = "Human-reviewable User Alarm proposal list. Only rows with Status = 'approved' may be emitted into a Robot Server alarm writer."

    AlarmRows = @(
        @{
            AlarmNumber = 90
            CurrentMessage = ""
            CurrentSeverityValue = 6
            ProposedMessage = "A MAIN START BLOCKED"
            ProposedSeverityValue = 6
            Reason = "Generated A_MAIN startup guard failed before RUN."
            Source = "A_MAIN"
            Status = "proposed"
        },
        @{
            AlarmNumber = 91
            CurrentMessage = ""
            CurrentSeverityValue = 6
            ProposedMessage = "A MAIN START FAILED"
            ProposedSeverityValue = 6
            Reason = "Generated A_MAIN did not prove async task running after RUN."
            Source = "A_MAIN"
            Status = "proposed"
        },
        @{
            AlarmNumber = 95
            CurrentMessage = ""
            CurrentSeverityValue = 6
            ProposedMessage = "UNLOAD CNC FAILED"
            ProposedSeverityValue = 6
            Reason = "Generated A_UNLOAD_CNC reported fault through the subprogram result contract."
            Source = "A_UNLOAD_CNC"
            Status = "proposed"
        },
        @{
            AlarmNumber = 98
            CurrentMessage = ""
            CurrentSeverityValue = 6
            ProposedMessage = "CONV START BLOCKED"
            ProposedSeverityValue = 6
            Reason = "Generated A_PLACE_CONVEYOR found conveyor task was not startable."
            Source = "A_PLACE_CONVEYOR"
            Status = "proposed"
        }
    )
}
