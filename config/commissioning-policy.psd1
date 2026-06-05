@{
    SchemaVersion = 1
    PolicyName = "operator-owned-step-test-commissioning"
    Owner = "Project robot programmer / controls engineer"
    UploadGate = "local-evidence"
    AutoUploadChangedRobotFacingTpAfterLocalEvidence = $true
    UploadRequiresFreshReadback = $true
    UploadRequiresReadbackDecode = $true
    Notes = "This project treats upload as staging only. When a robot-facing generated TP is changed or regenerated, upload it after local evidence passes. A successful upload command must refresh robot readback, hash-compare, decode, and refresh the manifest. Uploading does not approve automatic operation. The operator owns pendant selection, low-speed step testing, deadman control, and final run decisions."

    OperatorExecutionBoundary = @{
        ProgramRunAuthority = "operator-only"
        AutomaticOperationApprovedByUpload = $false
        ExpectedFirstRunMode = "manual-step-test"
        ExpectedFirstRunControls = @(
            "teach pendant"
            "deadman switch"
            "low speed"
            "step-by-step execution"
        )
    }

    ToolingResponsibilities = @(
        "validate structured specs"
        "enforce project cell-map resource allowlists"
        "enforce static LS safety rules"
        "compile with MakeTP"
        "round-trip/decode with PrintTP"
        "upload to robot only when local evidence passes"
        "record upload and readback evidence"
    )

    RequiresExplicitPolicyDecision = @(
        "new motion template or widened motion authority"
        "new RUN target or async task ownership rule"
        "new CALL target outside the current cell map"
        "writes outside the current register or IO allowlists"
        "system variable writes beyond documented project policy"
        "KAREL deployment beyond the approved TSKSTATUS helper"
        "SNPX writes outside the scratch write policy"
        "DCS, UOP, mastering, frame, tool, payload, or controller configuration changes"
        "automatic program selection or automatic program start"
    )
}
