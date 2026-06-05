@{
    SchemaVersion = 1
    ProjectName = "SampleProject"
    WorkcellName = "SampleCell"
    PolicyScope = "sample-no-live-writes"
    Notes = "Human-reviewable metadata proposal list. Only rows with Status = 'approved' may be emitted into a generated writer."

    CommentRows = @(
        @{
            Family = "R"
            Index = 90
            Current = ""
            Proposed = "STEP STATUS"
            Reason = "Generated workflow status register."
            Source = "A_MAIN"
            Status = "proposed"
        },
        @{
            Family = "PR"
            Index = 300
            Current = ""
            Proposed = "APPROACH"
            Reason = "Reviewed approach position for the first motion template."
            Source = "motion-application-spec"
            Status = "proposed"
        },
        @{
            Family = "DI"
            Index = 1
            Current = ""
            Proposed = "PART PRESENT"
            Reason = "Example input comment proposal."
            Source = "cell-map"
            Status = "proposed"
        },
        @{
            Family = "DO"
            Index = 1
            Current = ""
            Proposed = "AIR BLOW"
            Reason = "Example output comment proposal."
            Source = "cell-map"
            Status = "proposed"
        },
        @{
            Family = "RI"
            Index = 1
            Current = ""
            Proposed = "ROBOT INPUT"
            Reason = "Example robot input comment proposal."
            Source = "cell-map"
            Status = "proposed"
        },
        @{
            Family = "RO"
            Index = 1
            Current = ""
            Proposed = "ROBOT OUTPUT"
            Reason = "Example robot output comment proposal."
            Source = "cell-map"
            Status = "proposed"
        },
        @{
            Family = "GI"
            Index = 1
            Current = ""
            Proposed = "STYLE IN"
            Reason = "Example group input comment proposal."
            Source = "cell-map"
            Status = "proposed"
        },
        @{
            Family = "GO"
            Index = 1
            Current = ""
            Proposed = "STATUS OUT"
            Reason = "Example group output comment proposal."
            Source = "cell-map"
            Status = "proposed"
        }
    )

    UserAlarmRows = @(
        @{
            AlarmNumber = 90
            CurrentMessage = ""
            ProposedMessage = "A_MAIN START BLOCKED"
            CurrentSeverity = ""
            ProposedSeverity = "STOP.L"
            ProposedSeverityValue = 6
            Reason = "Example generated workflow alarm."
            Source = "A_MAIN"
            Status = "proposed"
        }
    )
}
