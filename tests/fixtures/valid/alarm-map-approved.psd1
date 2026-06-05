@{
    SchemaVersion = 1
    ProjectName = "Fixture"
    WorkcellName = "Fixture"
    PolicyScope = "offline-alarm-plan-test"
    Notes = "Approved alarm-map fixture for Robot Server alarm write-plan tests."

    AlarmRows = @(
        @{
            AlarmNumber = 90
            CurrentMessage = ""
            CurrentSeverityValue = 6
            ProposedMessage = "A MAIN START BLOCKED"
            ProposedSeverityValue = 6
            Reason = "Message-only write proof."
            Source = "A_MAIN"
            Status = "approved"
        },
        @{
            AlarmNumber = 91
            CurrentMessage = "OLD START FAIL"
            CurrentSeverityValue = 0
            ProposedMessage = "A MAIN START FAILED"
            ProposedSeverityValue = 6
            Reason = "Message and severity write proof."
            Source = "A_MAIN"
            Status = "approved"
        },
        @{
            AlarmNumber = 92
            CurrentMessage = "ALREADY OK"
            CurrentSeverityValue = 6
            ProposedMessage = "ALREADY OK"
            ProposedSeverityValue = 6
            Reason = "Already-matches proof."
            Source = "A_MAIN"
            Status = "approved"
        },
        @{
            AlarmNumber = 93
            CurrentMessage = ""
            CurrentSeverityValue = 6
            ProposedMessage = "NOT APPROVED"
            ProposedSeverityValue = 6
            Reason = "Skipped proposed row."
            Source = "A_MAIN"
            Status = "proposed"
        }
    )
}
