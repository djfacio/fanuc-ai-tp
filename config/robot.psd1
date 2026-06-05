@{
    RobotIp = "192.0.2.10"
    UserName = "anonymous"
    Password = "guest"
    WinOlpcVersion = "V9.40-1"
    MakeTpPath = "C:\Program Files (x86)\FANUC\WinOLPC\bin\maketp.exe"
    RobotIniPath = "REVIEW_AND_SET_ROBOT_INI_PATH"
    CellMapPath = "config\cell-map.psd1"
    WorkcellRobotPath = "REVIEW_AND_SET_ROBOGUIDE_WORKCELL_ROBOT_PATH"
    ProgramPrefix = "A_"
    LegacyProgramPrefixes = @("AI_")
    KnownMacroPrograms = @(
    )
    CleanupProtectedPrograms = @(
        "-BCKEDT-"
    )
}
