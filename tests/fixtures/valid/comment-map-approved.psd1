@{
    SchemaVersion = 1
    ProjectName = "Fixture"
    WorkcellName = "Fixture"
    PolicyScope = "offline-plan-test"
    Notes = "Approved comment-map fixture for Robot Server write-plan tests."

    CommentRows = @(
        @{
            Family = "R"
            Index = 90
            Current = "OLD STEP"
            Proposed = "STEP STATUS"
            Reason = "Generated workflow status register."
            Source = "A_MAIN"
            Status = "approved"
        },
        @{
            Family = "PR"
            Index = 300
            Current = ""
            Proposed = "APPROACH"
            Reason = "Reviewed approach position."
            Source = "motion-application-spec"
            Status = "approved"
        },
        @{
            Family = "DI"
            Index = 104
            Current = "Sync1"
            Proposed = "SYNC 1"
            Reason = "Normalize generated review label."
            Source = "cell-map"
            Status = "approved"
        },
        @{
            Family = "DO"
            Index = 104
            Current = "Ack1"
            Proposed = "ACK 1"
            Reason = "Normalize generated review label."
            Source = "cell-map"
            Status = "approved"
        },
        @{
            Family = "SR"
            Index = 1
            Current = ""
            Proposed = "ACTIVE JOB"
            Reason = "String register comment proof."
            Source = "metadata"
            Status = "approved"
        },
        @{
            Family = "GO"
            Index = 1
            Current = ""
            Proposed = "STATUS OUT"
            Reason = "Not in fixture snapshot and not approved."
            Source = "cell-map"
            Status = "proposed"
        }
    )
}
