param(
    [string]$OutputRoot = "generated",
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

if ([System.IO.Path]::IsPathRooted($OutputRoot)) {
    $resolvedOutputRoot = $OutputRoot
} else {
    $resolvedOutputRoot = Join-Path $projectRoot $OutputRoot
}

$sourcesDir = Join-Path $resolvedOutputRoot "sources"
$jobsDir = Join-Path $resolvedOutputRoot "jobs"
foreach ($path in @($sourcesDir, $jobsDir)) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

function New-FanucLsText {
    param(
        [string]$ProgramName,
        [string]$Comment,
        [string]$DefaultGroup,
        [string[]]$Bodies
    )

    $now = Get-Date
    $date = $now.ToString("yy-MM-dd")
    $time = $now.ToString("HH:mm:ss")
    $lineNumber = 1
    $mnLines = foreach ($body in $Bodies) {
        (" {0,3}:  {1}" -f $lineNumber, $body)
        $lineNumber++
    }
    $lineCount = $Bodies.Count
    $mnText = $mnLines -join "`n"

    @"
/PROG $ProgramName
/ATTR
OWNER = MNEDITOR;
COMMENT = "$Comment";
PROG_SIZE = 0;
CREATE = DATE $date  TIME $time;
MODIFIED = DATE $date  TIME $time;
FILE_NAME = ;
VERSION = 0;
LINE_COUNT = $lineCount;
MEMORY_SIZE = 0;
PROTECT = READ_WRITE;
TCD: STACK_SIZE = 0,
     TASK_PRIORITY = 50,
     TIME_SLICE = 0,
     BUSY_LAMP_OFF = 0,
     ABORT_REQUEST = 0,
     PAUSE_REQUEST = 0;
DEFAULT_GROUP = $DefaultGroup;
CONTROL_CODE = 00000000 00000000;
LOCAL_REGISTERS = 0,0,0;
/APPL
/APPL

AUTO_SINGULARITY_HEADER;
  ENABLE_SINGULARITY_AVOIDANCE   : TRUE;
/MN
$mnText
/POS
/END
"@
}

function Write-FanucProgram {
    param(
        [string]$ProgramName,
        [string]$Comment,
        [string]$DefaultGroup,
        [string[]]$Bodies
    )

    $sourceOut = Join-Path $sourcesDir ($ProgramName + ".LS")
    $jobDir = Join-Path $jobsDir $ProgramName
    $jobSourceOut = Join-Path $jobDir ($ProgramName + ".LS")
    if (-not (Test-Path -LiteralPath $jobDir)) {
        New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    }

    foreach ($path in @($sourceOut, $jobSourceOut)) {
        if ((Test-Path -LiteralPath $path) -and -not $Force) {
            throw "Output already exists: $path. Use -Force to overwrite."
        }
    }

    $content = New-FanucLsText -ProgramName $ProgramName -Comment $Comment -DefaultGroup $DefaultGroup -Bodies $Bodies
    Set-Content -LiteralPath $sourceOut -Value $content -Encoding ASCII
    Set-Content -LiteralPath $jobSourceOut -Value $content -Encoding ASCII

    [pscustomobject]@{
        ProgramName = $ProgramName
        SourcePath = (Get-Item -LiteralPath $sourceOut).FullName
        JobSourcePath = (Get-Item -LiteralPath $jobSourceOut).FullName
        LineCount = $Bodies.Count
    }
}

$wildcardGroup = "*,*,*,*,*,*,*,*"
$group1 = "1,*,*,*,*"

$programs = @(
    @{
        ProgramName = "A_MAIN"
        Comment = "Main Flow"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:Main flow only: child routines own details; R80 200=OK, 204=Finish, else Fault ;",
            "R[80]=10 ;",
            "R[90]=100 ;",
            " ;",
            "--eg:Startup - verify cell is ready ;",
            "CALL A_PRECHECK ;",
            "IF (R[80]<>200),JMP LBL[990] ;",
            " ;",
            "--eg:Startup - initialize cycle state ;",
            "CALL A_INIT_CYCL ;",
            "IF (R[80]<>200),JMP LBL[990] ;",
            " ;",
            "--eg:Startup - start feeder task ;",
            "CALL A_START_FD ;",
            "IF (R[80]<>200),JMP LBL[990] ;",
            " ;",
            "--eg:Main Loop ********************************* ;",
            "LBL[100] ;",
            " ;",
            "!Go Home ;",
            "CALL A_HOME_STEP ;",
            " ;",
            "--eg:Infeed - pick and optional regrip ;",
            "CALL A_INFEED ;",
            "IF (R[80]<>200),JMP LBL[990] ;",
            " ;",
            "--eg:CNC - unload finished, load raw ;",
            "CALL A_CNC_STAGE ;",
            "IF (R[80]<>200),JMP LBL[990] ;",
            " ;",
            "--eg:Tube Insertion - unload/load ;",
            "CALL A_TI_STAGE ;",
            "IF (R[80]<>200),JMP LBL[990] ;",
            " ;",
            "--eg:Outfeed - print/conveyor handoff ;",
            "CALL A_OUTFEED ;",
            "IF (R[80]<>200),JMP LBL[990] ;",
            " ;",
            "--eg:Loop Decision ***************************** ;",
            "CALL A_LOOP_DEC ;",
            "--eg:R80 200=Repeat, 204=Finish ;",
            "IF (R[80]=200),JMP LBL[100] ;",
            "IF (R[80]=204),JMP LBL[900] ;",
            "JMP LBL[990] ;",
            " ;",
            "--eg:Normal Finish **************************** ;",
            "LBL[900] ;",
            "--eg:Call finish routine ;",
            "CALL A_FINISH_CYCLE ;",
            "F[20:OFF:STOP]=(OFF) ;",
            "F[60:OFF:INFEED]=(ON) ;",
            "END ;",
            " ;",
            "--eg:Fault Exit ******************************** ;",
            "LBL[990] ;",
            "--eg:Call fault cleanup ;",
            "CALL A_FAULT ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_PRECHECK"
        Comment = "PRECHECK"
        DefaultGroup = $wildcardGroup
        Bodies = @(
            "--eg:PRECHECK START PERMISSIVES AND CELL STATE ;",
            "R[80]=200 ;",
            "IF (F[68:OFF] OR !F[69:OFF]),JMP LBL[996] ;",
            "IF (!UO[7:OFF:At perch]),JMP LBL[995] ;",
            "IF (R[102:Counter_Limit]<>0) THEN ;",
            "IF (R[101:Count]>=R[102:Counter_Limit]),JMP LBL[997] ;",
            "ENDIF ;",
            "IF (DI[101:OFF:CNC Alarm]),JMP LBL[998] ;",
            "JMP LBL[999] ;",
            "LBL[995] ;",
            "R[80]=409 ;",
            "R[90]=409 ;",
            "MESSAGE[PERCH CHECK FAIL] ;",
            "UALM[4] ;",
            "JMP LBL[999] ;",
            "LBL[996] ;",
            "R[80]=409 ;",
            "R[90]=409 ;",
            "MESSAGE[START PERM FAIL] ;",
            "UALM[5] ;",
            "JMP LBL[999] ;",
            "LBL[997] ;",
            "R[80]=409 ;",
            "R[90]=409 ;",
            "MESSAGE[COUNTER LIMIT] ;",
            "UALM[6] ;",
            "JMP LBL[999] ;",
            "LBL[998] ;",
            "R[80]=409 ;",
            "R[90]=409 ;",
            "MESSAGE[CNC ALARMED] ;",
            "UALM[9] ;",
            "LBL[999] ;"
        )
    },
    @{
        ProgramName = "A_INIT_CYCL"
        Comment = "INIT CYCLE"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:INIT CYCLE STATE AND REVIEWED PRS ;",
            "R[80]=200 ;",
            "--eg:CALL LEGACY INIT MIGRATION ;",
            "CALL A_INIT ;",
            "--eg:CALL REVIEWED PR CALCULATION ;",
            "CALL A_CALC_POS ;"
        )
    },
    @{
        ProgramName = "A_START_FD"
        Comment = "START FEED"
        DefaultGroup = $wildcardGroup
        Bodies = @(
            "--eg:START FLEXI ONLY FROM 204/404 ;",
            "R[80]=200 ;",
            "--eg:CHECK FEEDER TASK STATUS ;",
            "CALL TSKSTATUS('A_FLEXI_LOADER',91,0) ;",
            "IF (R[91]=204),JMP LBL[810] ;",
            "IF (R[91]=404),JMP LBL[810] ;",
            "R[80]=409 ;",
            "R[90]=409 ;",
            "MESSAGE[FLEXI START BLOCKED] ;",
            "UALM[90] ;",
            "JMP LBL[999] ;",
            "LBL[810] ;",
            "R[90]=110 ;",
            "RUN A_FLEXI_LOADER ;",
            "WAIT 1.00(sec) ;",
            "R[90]=115 ;",
            "--eg:EXPECT RUNNING OR FAST PART READY ;",
            "--eg:CHECK FEEDER START RESULT ;",
            "CALL TSKSTATUS('A_FLEXI_LOADER',91,0) ;",
            "IF (R[91]=200),JMP LBL[999] ;",
            "IF (F[50:OFF:Part_Ready] AND R[91]=204),JMP LBL[999] ;",
            "IF (F[50:OFF:Part_Ready] AND R[91]=404),JMP LBL[999] ;",
            "R[80]=502 ;",
            "R[90]=502 ;",
            "MESSAGE[FLEXI RUN FAIL] ;",
            "UALM[91] ;",
            "LBL[999] ;"
        )
    },
    @{
        ProgramName = "A_HOME_STEP"
        Comment = "HOME STEP"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:RETURN ROBOT HOME ;",
            "R[80]=200 ;",
            "--eg:CALL HOME MOTION ROUTINE ;",
            "CALL A_GO_HOME ;"
        )
    },
    @{
        ProgramName = "A_INFEED"
        Comment = "INFEED"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:INFEED PICK AND REGRIP STAGE ;",
            "R[80]=200 ;",
            "IF (!F[60:OFF:INFEED]),JMP LBL[999] ;",
            '$WAITTMOUT=6000 ;',
            "WAIT (F[50:OFF:Part_Ready] OR F[20:OFF:STOP]) TIMEOUT,LBL[980] ;",
            "IF (!F[20:OFF:STOP]),JMP LBL[110] ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "JMP LBL[999] ;",
            "LBL[110] ;",
            "--eg:CALCULATE PICK POSITION ;",
            "CALL A_CALC_PICK ;",
            "--eg:CALL BOWL PICK MOTION ;",
            "CALL A_PICK ;",
            "F[50:OFF:Part_Ready]=(OFF) ;",
            "F[61:OFF:PART_4_CNC]=(ON) ;",
            "--eg:RESTART FEEDER FOR NEXT PART ;",
            "CALL A_START_FD ;",
            "IF (R[80]<>200),JMP LBL[999] ;",
            "IF (R[102:Counter_Limit]<>0) THEN ;",
            "R[101:Count]=R[101:Count]+1 ;",
            "IF (R[101:Count]>=R[102:Counter_Limit]) THEN ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "ENDIF ;",
            "ENDIF ;",
            "IF ((R[100:PART NUMBER]=1 OR R[100:PART NUMBER]=2) AND R[45:PATTERN FOUND]=1),JMP LBL[999] ;",
            "F[61:OFF:PART_4_CNC]=(OFF) ;",
            "--eg:CALCULATE REGRIP POSITIONS ;",
            "CALL A_CALC_REGRIP ;",
            "--eg:CALL REGRIP MOTION ;",
            "CALL A_REGRIP ;",
            "F[61:OFF:PART_4_CNC]=(ON) ;",
            "JMP LBL[999] ;",
            "LBL[980] ;",
            "R[80]=500 ;",
            "R[90]=408 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[PART WAIT TIMEOUT] ;",
            "UALM[92] ;",
            "LBL[999] ;"
        )
    },
    @{
        ProgramName = "A_CNC_STAGE"
        Comment = "CNC STAGE"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:CNC UNLOAD/LOAD HANDSHAKE STAGE ;",
            "R[80]=200 ;",
            "IF (F[61:OFF:PART_4_CNC] OR F[62:OFF:PART_IN_CNC]),JMP LBL[100] ;",
            "JMP LBL[999] ;",
            "LBL[100] ;",
            '$WAITTMOUT=6000 ;',
            "WAIT DI[104:OFF:Sync1]=ON TIMEOUT,LBL[981] ;",
            "--eg:CALCULATE CNC POSITIONS ;",
            "CALL A_CALC_CNC ;",
            "--eg:ENTER CNC AREA ;",
            "CALL A_ENTER_CNC ;",
            "IF (!F[62:OFF:PART_IN_CNC]),JMP LBL[120] ;",
            "R[94]=0 ;",
            "--eg:UNLOAD FINISHED PART FROM CNC ;",
            "CALL A_UNLOAD_CNC ;",
            "IF (R[94]=200),JMP LBL[115] ;",
            "R[80]=502 ;",
            "R[90]=502 ;",
            "MESSAGE[CNC UNLOAD FAIL] ;",
            "UALM[95] ;",
            "JMP LBL[999] ;",
            "LBL[115] ;",
            "F[62:OFF:PART_IN_CNC]=(OFF) ;",
            "F[63:OFF:PART_4_INS]=(ON) ;",
            "LBL[120] ;",
            "IF (!F[61:OFF:PART_4_CNC]),JMP LBL[130] ;",
            "--eg:LOAD RAW PART INTO CNC ;",
            "CALL A_LOAD_CNC ;",
            "F[61:OFF:PART_4_CNC]=(OFF) ;",
            "F[62:OFF:PART_IN_CNC]=(ON) ;",
            "DO[104:OFF:Ack1]=PULSE,0.5sec ;",
            '$WAITTMOUT=6000 ;',
            "WAIT DI[104:OFF:Sync1]=OFF TIMEOUT,LBL[984] ;",
            "LBL[130] ;",
            "--eg:EXIT CNC AREA ;",
            "CALL A_EXIT_CNC ;",
            "JMP LBL[999] ;",
            "LBL[981] ;",
            "R[80]=500 ;",
            "R[90]=408 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[CNC WAIT TIMEOUT] ;",
            "UALM[93] ;",
            "JMP LBL[999] ;",
            "LBL[984] ;",
            "R[80]=500 ;",
            "R[90]=408 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[CNC RESET TIMEOUT] ;",
            "UALM[93] ;",
            "LBL[999] ;"
        )
    },
    @{
        ProgramName = "A_TI_STAGE"
        Comment = "TI STAGE"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:TUBE INSERTION UNLOAD/LOAD STAGE ;",
            "R[80]=200 ;",
            "IF (!F[64:OFF:PART_IN_INS]),JMP LBL[120] ;",
            '$WAITTMOUT=6000 ;',
            "WAIT DI[105:OFF:Sync2]=ON TIMEOUT,LBL[982] ;",
            "--eg:UNLOAD TUBE INSERTION ;",
            "CALL A_UNLOAD_TI ;",
            "F[64:OFF:PART_IN_INS]=(OFF) ;",
            "F[65:OFF:PART_2_PRINT]=(ON) ;",
            "LBL[120] ;",
            "IF (!F[63:OFF:PART_4_INS]),JMP LBL[999] ;",
            '$WAITTMOUT=6000 ;',
            "WAIT DI[105:OFF:Sync2]=ON TIMEOUT,LBL[982] ;",
            "--eg:LOAD TUBE INSERTION ;",
            "CALL A_LOAD_TI ;",
            "F[63:OFF:PART_4_INS]=(OFF) ;",
            "F[64:OFF:PART_IN_INS]=(ON) ;",
            "DO[105:OFF:Ack2]=PULSE,0.5sec ;",
            '$WAITTMOUT=6000 ;',
            "WAIT DI[105:OFF:Sync2]=OFF TIMEOUT,LBL[983] ;",
            "JMP LBL[999] ;",
            "LBL[982] ;",
            "R[80]=500 ;",
            "R[90]=408 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[TI WAIT TIMEOUT] ;",
            "UALM[94] ;",
            "JMP LBL[999] ;",
            "LBL[983] ;",
            "R[80]=500 ;",
            "R[90]=408 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[TI RESET TIMEOUT] ;",
            "UALM[94] ;",
            "LBL[999] ;"
        )
    },
    @{
        ProgramName = "A_OUTFEED"
        Comment = "OUTFEED"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:OUTFEED PRINT/CONVEYOR HANDOFF ;",
            "R[80]=200 ;",
            "IF (!F[65:OFF:PART_2_PRINT]),JMP LBL[999] ;",
            "--eg:CALL CONVEYOR DROP ROUTINE ;",
            "CALL A_CONV_DROP ;",
            "LBL[999] ;"
        )
    },
    @{
        ProgramName = "A_LOOP_DEC"
        Comment = "LOOP DECIDE"
        DefaultGroup = $wildcardGroup
        Bodies = @(
            "--eg:204 FINISH WHEN INFEED OFF AND WIP EMPTY ;",
            "R[80]=200 ;",
            "IF (!F[60:OFF:INFEED] AND !F[62:OFF:PART_IN_CNC] AND !F[64:OFF:PART_IN_INS]),R[80]=204 ;"
        )
    },
    @{
        ProgramName = "A_FAULT"
        Comment = "FAULT CLEANUP"
        DefaultGroup = $wildcardGroup
        Bodies = @(
            "--eg:FAULT CLEANUP ONLY, ALARM SET BY CALLER ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "F[20:OFF:STOP]=(OFF) ;"
        )
    }
)

$records = New-Object System.Collections.Generic.List[object]
foreach ($program in $programs) {
    $records.Add((Write-FanucProgram -ProgramName $program.ProgramName -Comment $program.Comment -DefaultGroup $program.DefaultGroup -Bodies $program.Bodies))
}

$manifestPath = Join-Path $resolvedOutputRoot "a-main-workflow-draft.json"
[ordered]@{
    generatedAt = (Get-Date).ToString("o")
    programCount = $records.Count
    style = "flowchart-main-with-encapsulated-child-routines"
    programs = @($records.ToArray())
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding ASCII

[pscustomobject]@{
    ProgramName = "A_MAIN"
    ProgramCount = $records.Count
    ManifestPath = (Get-Item -LiteralPath $manifestPath).FullName
    SourcePath = @($records | Where-Object { $_.ProgramName -eq "A_MAIN" | Select-Object -First 1 }).SourcePath
    Programs = @($records.ToArray())
}
