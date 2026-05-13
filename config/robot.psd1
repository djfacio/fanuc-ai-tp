@{
    RobotIp = "192.168.5.10"
    UserName = "anonymous"
    Password = "guest"
    WinOlpcVersion = "V9.40-1"
    MakeTpPath = "C:\Program Files (x86)\FANUC\WinOLPC\bin\maketp.exe"
    RobotIniPath = "config\robot.ini"
    CellMapPath = "config\cell-map.psd1"
    WorkcellRobotPath = "C:\Users\Cubic\Documents\My Workcells\TA_Aerospace\Robot_1"
    ProgramPrefix = "A_"
    LegacyProgramPrefixes = @("AI_")
    KnownMacroPrograms = @(
        "F_BG_SPD_OVRD"
        "F_OPENG1"
        "F_OPENG2"
        "F_PUSHER1"
        "F_PUSHER2"
    )
}
