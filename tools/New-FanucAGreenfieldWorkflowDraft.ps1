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
        [int]$StackSize = 0,
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
TCD: STACK_SIZE = $StackSize,
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
        [int]$StackSize = 0,
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

    $content = New-FanucLsText -ProgramName $ProgramName -Comment $Comment -DefaultGroup $DefaultGroup -StackSize $StackSize -Bodies $Bodies
    $content = ($content -replace "\r?\n", "`r`n").TrimEnd() + "`r`n"
    $ascii = [System.Text.Encoding]::ASCII
    [System.IO.File]::WriteAllText($sourceOut, $content, $ascii)
    [System.IO.File]::WriteAllText($jobSourceOut, $content, $ascii)

    [pscustomobject]@{
        ProgramName = $ProgramName
        SourcePath = (Get-Item -LiteralPath $sourceOut).FullName
        JobSourcePath = (Get-Item -LiteralPath $jobSourceOut).FullName
        LineCount = $Bodies.Count
        StackSize = $StackSize
    }
}

$wildcardGroup = "*,*,*,*,*,*,*,*"
$group1 = "1,*,*,*,*"

$programs = @(
    @{
        ProgramName = "A_MAIN"
        Comment = "Main Flow"
        DefaultGroup = $group1
        StackSize = 1000
        Bodies = @(
            "--eg:Status-gated flow: phases own details; R80 200=Run, 204=Work Complete, else Fault; R90 Detail, R94 Step Result ;",
            "R[80]=200 ;",
            "R[90]=100 ;",
            " ;",
            "--eg:Startup: permissives, initialization, feeder start ;",
            "CALL A_STARTUP ;",
            "IF (R[80]<>200),JMP LBL[990] ;",
            " ;",
            "--eg:Main Loop ********************************* ;",
            "LBL[100] ;",
            " ;",
            "--eg:Feed Phase: create part for CNC when infeed is enabled ;",
            "IF (R[80]=200),CALL A_FEED ;",
            " ;",
            "--eg:CNC Exchange: advance F61/F62 toward Tube Insertion ;",
            "IF (R[80]=200),CALL A_EXCH_CNC ;",
            " ;",
            "--eg:Tube Insertion Exchange: advance F63/F64 toward outfeed ;",
            "IF (R[80]=200),CALL A_EXCH_TI ;",
            " ;",
            "--eg:Outfeed Phase: place F65 on conveyor and clear WIP ;",
            "IF (R[80]=200),CALL A_OUT ;",
            " ;",
            "--eg:Loop Decision ***************************** ;",
            "IF (R[80]=200),CALL A_DECIDE ;",
            "IF (R[80]=200),JMP LBL[100] ;",
            "IF (R[80]=204),JMP LBL[900] ;",
            "JMP LBL[990] ;",
            " ;",
            "--eg:Normal Finish **************************** ;",
            "LBL[900] ;",
            "--eg:Finish Work complete: handshake, keep infeed off ;",
            "CALL A_FINISH_CYCLE ;",
            "--eg:Return robot to home before normal program end ;",
            "CALL A_GO_HOME ;",
            "F[20:OFF:STOP]=(OFF) ;",
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
        ProgramName = "A_STARTUP"
        Comment = "Startup"
        DefaultGroup = $group1
        StackSize = 1000
        Bodies = @(
            "--eg:Startup preserves WIP flags F61-F65; R90 4101 Recipe, 4102 Home, 4103 Count, 4104 CNC ;",
            "R[80]=200 ;",
            "--eg:Recipe must be valid with no apply pending ;",
            "IF (F[68:OFF] OR !F[69:OFF]),JMP LBL[495] ;",
            "--eg:Robot must be at perch before startup ;",
            "IF (!UO[7:OFF:At perch]),JMP LBL[496] ;",
            "IF (R[102:Counter_Limit]<>0) THEN ;",
            "IF (R[101:Count]>=R[102:Counter_Limit]),JMP LBL[497] ;",
            "ENDIF ;",
            "IF (DI[101:OFF:CNC Alarm]),JMP LBL[498] ;",
            " ;",
            "--eg:Initialize non-WIP state; do not erase transfer flags F61-F65 ;",
            "CALL A_INIT_STATE ;",
            " ;",
            "--eg:Select vision at startup level to keep bridge stack shallow ;",
            "CALL A_SELECT_VISION(R[100:PART NUMBER]) ;",
            "--eg:Initialize vision bridge at the same shallow caller level ;",
            "CALL A_INIT_VISION ;",
            " ;",
            "--eg:Calculate static positions ;",
            "CALL A_CALC_POS ;",
            " ;",
            "--eg:A_FSTART starts feeder if not running ;",
            "CALL A_FSTART ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 409/4101 - Recipe Not Ready ;",
            "LBL[495] ;",
            "R[80]=409 ;",
            "R[90]=4101 ;",
            "MESSAGE[RECIPE NOT READY] ;",
            "UALM[4] ;",
            "END ;",
            " ;",
            "--eg:ERR 409/4102 - Robot Not At Perch ;",
            "LBL[496] ;",
            "R[80]=409 ;",
            "R[90]=4102 ;",
            "MESSAGE[ROBOT NOT HOME] ;",
            "UALM[5] ;",
            "END ;",
            " ;",
            "--eg:ERR 409/4103 - Counter Limit Reached ;",
            "LBL[497] ;",
            "R[80]=409 ;",
            "R[90]=4103 ;",
            "MESSAGE[COUNTER LIMIT] ;",
            "UALM[6] ;",
            "END ;",
            " ;",
            "--eg:ERR 409/4104 - CNC Alarm Input On ;",
            "LBL[498] ;",
            "R[80]=409 ;",
            "R[90]=4104 ;",
            "MESSAGE[CNC ALARMED] ;",
            "UALM[9] ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_INIT_STATE"
        Comment = "Init State"
        DefaultGroup = $wildcardGroup
        Bodies = @(
            "--eg:Initialize non-WIP state only; preserve transfer flags and physical hold outputs ;",
            "R[80]=200 ;",
            "R[123]=R[112]-R[113] ;",
            "R[124]=R[110]-R[114] ;",
            "R[125]=R[112]-R[115] ;",
            "R[126]=R[112]-R[116] ;",
            "R[103:Retry_Count]=0 ;",
            "R[105:Hopper_Count]=0 ;",
            "F[50:OFF:Part_Ready]=(OFF) ;",
            "F[51:OFF:Regrip_On_Conveyor]=(OFF) ;",
            "F[52:OFF:Conveyor Running]=(OFF) ;",
            "F[60:OFF:INFEED]=(ON) ;",
            "--eg:Skip vacuum reset when robot-held WIP may still be gripped ;",
            "IF (F[59:OFF] OR F[61:OFF:PART_4_CNC] OR F[63:OFF:PART_4_INS] OR F[65:OFF:PART_2_PRINT]),JMP LBL[100] ;",
            "--eg:No robot-held WIP: reset vacuum hold outputs ;",
            "DO[115:OFF:G1 Suck]=OFF ;",
            "DO[116:OFF:G2 Suck]=OFF ;",
            "DO[120:OFF:Shut-Off Valve]=ON ;",
            " ;",
            "--eg:Reset non-holding feeder/conveyor outputs ;",
            "LBL[100] ;",
            "DO[111:OFF:Start Bowl]=OFF ;",
            "DO[112:OFF:Shake Bowl]=OFF ;",
            "DO[113:OFF:Vibrate Bowl]=OFF ;",
            "DO[114:OFF:Stop Bowl]=PULSE,0.5sec ;",
            "DO[117:OFF:Conveyor Foward]=OFF ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_FSTART"
        Comment = "Feeder Start"
        DefaultGroup = $wildcardGroup
        StackSize = 1000
        Bodies = @(
            "--eg:Start feeder only when not already running; R90 4201 Status, 4202 Start, 4203 Running ;",
            "R[80]=200 ;",
            "--eg:TSKSTATUS 200=Running, 204/404=OK to start, else no start ;",
            "CALL TSKSTATUS('A_FLEXI_LOADER',91,0) ;",
            "IF (R[91]=200),JMP LBL[409] ;",
            "IF (R[91]=204 OR R[91]=404),JMP LBL[100] ;",
            "R[80]=502 ;",
            "R[90]=4201 ;",
            "MESSAGE[FEED STATUS FAIL] ;",
            "UALM[91] ;",
            "END ;",
            " ;",
            "--eg:Start Section *************************** ;",
            "LBL[100] ;",
            "RUN A_FLEXI_LOADER ;",
            "WAIT 1.00(sec) ;",
            " ;",
            "--eg:Verify feeder is running or fast complete ;",
            "CALL TSKSTATUS('A_FLEXI_LOADER',91,0) ;",
            "IF (R[91]=200),JMP LBL[200] ;",
            "IF (F[50:OFF:Part_Ready] AND (R[91]=204 OR R[91]=404)),JMP LBL[200] ;",
            "R[80]=502 ;",
            "R[90]=4202 ;",
            "MESSAGE[FEED START FAIL] ;",
            "UALM[91] ;",
            "END ;",
            " ;",
            "--eg:Normal End ****************************** ;",
            "LBL[200] ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 409/4203 - Feeder Already Running ;",
            "LBL[409] ;",
            "R[80]=409 ;",
            "R[90]=4203 ;",
            "MESSAGE[FEEDER ALREADY RUN] ;",
            "UALM[90] ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_FLEXI_LOADER"
        Comment = "Flexi Loader"
        DefaultGroup = $wildcardGroup
        StackSize = 1000
        Bodies = @(
            "--eg:Async Flexi Loader owner; R92 is local result, 200 Found, 204 Retry, 409 Hopper Limit, 500 Vision Fault ;",
            "--eg:Open vision connection ;",
            "CALL K_VS_CONNECT ;",
            " ;",
            "--eg:Main Loop ********************************* ;",
            "LBL[100] ;",
            "--eg:Continue only while A_MAIN is running ;",
            "CALL TSKSTATUS('A_MAIN',92,0) ;",
            "IF (R[92]<>200),JMP LBL[900] ;",
            "IF (F[50:OFF:Part_Ready]),JMP LBL[900] ;",
            " ;",
            "--eg:Scan feeder vision and decide recovery ;",
            "CALL A_FLX_SCAN ;",
            "IF (R[92]=200),JMP LBL[100] ;",
            "IF (R[92]=204),JMP LBL[100] ;",
            "IF (R[92]=409),JMP LBL[501] ;",
            "JMP LBL[500] ;",
            " ;",
            "--eg:Normal End ****************************** ;",
            "LBL[900] ;",
            "--eg:Close vision connection ;",
            "CALL K_VS_CLOSE ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 500 - Vision Communication Fault ;",
            "LBL[500] ;",
            "--eg:Close vision connection before alarm ;",
            "CALL K_VS_CLOSE ;",
            "MESSAGE[VISION COM ERROR] ;",
            "UALM[7] ;",
            "END ;",
            " ;",
            "--eg:ERR 409 - Hopper Limit Reached ;",
            "LBL[501] ;",
            "--eg:Close vision connection and stop infeed ;",
            "CALL K_VS_CLOSE ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[HOPPER LIMIT] ;",
            "UALM[8] ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_FLX_SCAN"
        Comment = "Flexi Scan"
        DefaultGroup = $wildcardGroup
        StackSize = 1000
        Bodies = @(
            "--eg:One vision trigger/read; R92 200 Found, 204 Retry, 409 Hopper Limit, 500 Vision Fault ;",
            "R[92]=0 ;",
            "--eg:Trigger vision ;",
            "CALL K_VS_SENDCMD('TRG') ;",
            "--eg:Wait for vision trigger reply ;",
            "CALL K_VS_WAITCMD('TRG',50) ;",
            "IF (R[50:VS CMD REPLY]<>0),JMP LBL[500] ;",
            "--eg:Read vision result values ;",
            "CALL K_VS_RECVVAL(30) ;",
            "IF (R[30]<1),JMP LBL[204] ;",
            "R[103:Retry_Count]=0 ;",
            "F[50:OFF:Part_Ready]=(ON) ;",
            "R[105:Hopper_Count]=0 ;",
            "R[92]=200 ;",
            "END ;",
            " ;",
            "--eg:No Part Found *************************** ;",
            "LBL[204] ;",
            "--eg:Apply retry/feed policy ;",
            "CALL A_FLX_RETRY ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 500 - Vision Reply Fault ;",
            "LBL[500] ;",
            "R[92]=500 ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_FLX_RETRY"
        Comment = "Flexi Retry"
        DefaultGroup = $wildcardGroup
        Bodies = @(
            "--eg:Retry decision after no vision part; R92 204 Retry Complete, 409 Hopper Limit ;",
            "R[92]=204 ;",
            "R[103:Retry_Count]=R[103:Retry_Count]+1 ;",
            "IF (R[103:Retry_Count]>=R[104:Retry_Limit]),JMP LBL[300] ;",
            "--eg:Below retry limit: agitate bowl ;",
            "CALL A_SHAKE_RATTLE_N_ROLL ;",
            "END ;",
            " ;",
            "--eg:Feed Hopper ***************************** ;",
            "LBL[300] ;",
            "IF (R[105:Hopper_Count]>=R[106:Hopper_Limit]),JMP LBL[409] ;",
            "--eg:Feed parts into hopper ;",
            "CALL A_FEEDER ;",
            "R[105:Hopper_Count]=R[105:Hopper_Count]+1 ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 409 - Hopper Limit Reached ;",
            "LBL[409] ;",
            "R[92]=409 ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_FEED"
        Comment = "Feed Phase"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:Feed phase creates F61 CNC-ready WIP; R90 4301 Part Ready Wait Timeout ;",
            "R[80]=200 ;",
            " ;",
            "--eg:Start feed phase from reviewed home/perch path ;",
            "CALL A_GO_HOME ;",
            " ;",
            "--eg:Resume picked part before waiting for another feeder candidate ;",
            "IF (F[59:OFF]) THEN ;",
            "--eg:Orient previously picked part for CNC ;",
            "CALL A_FEED_ORIENT ;",
            "ELSE ;",
            "--eg:Feed only while infeed remains enabled ;",
            "IF (F[60:OFF:INFEED]) THEN ;",
            "--eg:Wait Part Ready or Finish Work request ;",
            '$WAITTMOUT=6000 ;',
            "WAIT (F[50:OFF:Part_Ready] OR F[20:OFF:STOP]) TIMEOUT,LBL[408] ;",
            "IF (F[20:OFF:STOP]) THEN ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "ELSE ;",
            " ;",
            "--eg:Pick and claim CNC-bound WIP ;",
            "CALL A_FEED_PICK ;",
            " ;",
            "--eg:Restart feeder for next part ;",
            "IF (R[80]=200),CALL A_FSTART ;",
            " ;",
            "--eg:Apply count and infeed stop policy ;",
            "IF (R[80]=200),CALL A_FEED_COUNT ;",
            " ;",
            "--eg:Orient part for CNC if needed ;",
            "IF (R[80]=200),CALL A_FEED_ORIENT ;",
            "ENDIF ;",
            "ENDIF ;",
            "ENDIF ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 408/4301 - Part Ready Wait Timeout ;",
            "LBL[408] ;",
            "R[80]=408 ;",
            "R[90]=4301 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[PART WAIT TIMEOUT] ;",
            "UALM[92] ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_FEED_PICK"
        Comment = "Feed Pick"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:Pick bowl part; F59 holds picked WIP until orientation ;",
            "R[80]=200 ;",
            "--eg:Calculate pick positions ;",
            "CALL A_CALC_PICK ;",
            "R[94]=0 ;",
            "--eg:Pick Part From Bowl ;",
            "CALL A_PICK ;",
            "IF (R[94]<>200),JMP LBL[502] ;",
            "F[50:OFF:Part_Ready]=(OFF) ;",
            "F[59:OFF]=(ON) ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 502/4302 - Pick Subcall Fail ;",
            "LBL[502] ;",
            "R[80]=502 ;",
            "R[90]=4302 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[PICK FAIL] ;",
            "UALM[92] ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_FEED_COUNT"
        Comment = "Feed Count"
        DefaultGroup = $wildcardGroup
        Bodies = @(
            "--eg:Apply counter limit after a successful pick ;",
            "R[80]=200 ;",
            "IF (R[102:Counter_Limit]<>0) THEN ;",
            "R[101:Count]=R[101:Count]+1 ;",
            "IF (R[101:Count]>=R[102:Counter_Limit]) THEN ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "ENDIF ;",
            "ENDIF ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_FEED_ORIENT"
        Comment = "Feed Orient"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:Regrip only when vision part/pattern is not CNC-ready ;",
            "R[80]=200 ;",
            "IF ((R[100:PART NUMBER]<>1 AND R[100:PART NUMBER]<>2) OR R[45:PATTERN FOUND]<>1) THEN ;",
            "--eg:Calculate regrip positions ;",
            "CALL A_CALC_REGRIP ;",
            "R[94]=0 ;",
            "--eg:Regrip Part For CNC ;",
            "CALL A_REGRIP ;",
            "IF (R[94]<>200),JMP LBL[503] ;",
            "ENDIF ;",
            "F[59:OFF]=(OFF) ;",
            "F[61:OFF:PART_4_CNC]=(ON) ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 502/4303 - Regrip Subcall Fail ;",
            "LBL[503] ;",
            "R[80]=502 ;",
            "R[90]=4303 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[REGRIP FAIL] ;",
            "UALM[92] ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_EXCH_CNC"
        Comment = "CNC Exchange"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:CNC exchange owns F61/F62/F63 transitions; R90 4401 Ready, 4402 Sync, 4403 Unload, 4404 Load ;",
            "R[80]=200 ;",
            "IF (F[61:OFF:PART_4_CNC] OR F[62:OFF:PART_IN_CNC]) THEN ;",
            " ;",
            "--eg:CNC request Sync1 ON before entry ;",
            '$WAITTMOUT=6000 ;',
            "WAIT DI[104:OFF:Sync1]=ON TIMEOUT,LBL[408] ;",
            "--eg:Calculate CNC exchange positions ;",
            "CALL A_CALC_CNC ;",
            "--eg:Enter CNC area ;",
            "CALL A_ENTER_CNC ;",
            " ;",
            "--eg:Unload finished CNC part when CNC contains WIP ;",
            "IF (F[62:OFF:PART_IN_CNC]) THEN ;",
            "R[94]=0 ;",
            "--eg:Call CNC unload; R94 must return 200 before F62/F63 changes ;",
            "CALL A_UNLOAD_CNC ;",
            "IF (R[94]<>200),JMP LBL[502] ;",
            "F[62:OFF:PART_IN_CNC]=(OFF) ;",
            "F[63:OFF:PART_4_INS]=(ON) ;",
            "ENDIF ;",
            " ;",
            "--eg:Load raw part into CNC when robot holds CNC-bound WIP ;",
            "IF (F[61:OFF:PART_4_CNC]) THEN ;",
            "R[94]=0 ;",
            "--eg:Call CNC load before claiming part is in CNC ;",
            "CALL A_LOAD_CNC ;",
            "IF (R[94]<>200),JMP LBL[503] ;",
            "F[61:OFF:PART_4_CNC]=(OFF) ;",
            "F[62:OFF:PART_IN_CNC]=(ON) ;",
            "--eg:Ack CNC load and prove Sync1 dropped ;",
            "DO[104:OFF:Ack1]=PULSE,0.5sec ;",
            '$WAITTMOUT=6000 ;',
            "WAIT DI[104:OFF:Sync1]=OFF TIMEOUT,LBL[409] ;",
            "ENDIF ;",
            " ;",
            "--eg:Exit CNC area ;",
            "CALL A_EXIT_CNC ;",
            "ENDIF ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 408/4401 - CNC Ready Timeout ;",
            "LBL[408] ;",
            "R[80]=408 ;",
            "R[90]=4401 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[CNC READY TIMEOUT] ;",
            "UALM[93] ;",
            "END ;",
            " ;",
            "--eg:ERR 409/4402 - CNC Sync1 Stuck On ;",
            "LBL[409] ;",
            "R[80]=409 ;",
            "R[90]=4402 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "--eg:Exit CNC area before alarming Sync1 stuck ;",
            "CALL A_EXIT_CNC ;",
            "MESSAGE[CNC SYNC STUCK] ;",
            "UALM[93] ;",
            "END ;",
            " ;",
            "--eg:ERR 502/4403 - CNC Unload Subcall Fail ;",
            "LBL[502] ;",
            "R[80]=502 ;",
            "R[90]=4403 ;",
            "--eg:Exit CNC area before alarming unload failure ;",
            "CALL A_EXIT_CNC ;",
            "MESSAGE[CNC UNLOAD FAIL] ;",
            "UALM[95] ;",
            "END ;",
            " ;",
            "--eg:ERR 502/4404 - CNC Load Subcall Fail ;",
            "LBL[503] ;",
            "R[80]=502 ;",
            "R[90]=4404 ;",
            "--eg:Exit CNC area before alarming load failure ;",
            "CALL A_EXIT_CNC ;",
            "MESSAGE[CNC LOAD FAIL] ;",
            "UALM[95] ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_EXCH_TI"
        Comment = "TI Exchange"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:TI exchange owns F63/F64/F65 transitions; R90 4501 Ready, 4502 Sync, 4503 Unload, 4504 Load ;",
            "R[80]=200 ;",
            "IF (F[63:OFF:PART_4_INS] OR F[64:OFF:PART_IN_INS]) THEN ;",
            " ;",
            "--eg:TI request Sync2 ON before entry ;",
            '$WAITTMOUT=6000 ;',
            "WAIT DI[105:OFF:Sync2]=ON TIMEOUT,LBL[408] ;",
            " ;",
            "--eg:Unload finished TI part when TI contains WIP ;",
            "IF (F[64:OFF:PART_IN_INS]) THEN ;",
            "R[94]=0 ;",
            "--eg:Call TI unload before moving WIP to outfeed ;",
            "CALL A_UNLOAD_TI ;",
            "IF (R[94]<>200),JMP LBL[502] ;",
            "F[64:OFF:PART_IN_INS]=(OFF) ;",
            "F[65:OFF:PART_2_PRINT]=(ON) ;",
            "ENDIF ;",
            " ;",
            "--eg:Load part into TI when robot holds TI-bound WIP ;",
            "IF (F[63:OFF:PART_4_INS]) THEN ;",
            "R[94]=0 ;",
            "--eg:Call TI load before claiming part is in TI ;",
            "CALL A_LOAD_TI ;",
            "IF (R[94]<>200),JMP LBL[503] ;",
            "F[63:OFF:PART_4_INS]=(OFF) ;",
            "F[64:OFF:PART_IN_INS]=(ON) ;",
            "--eg:Ack TI load and prove Sync2 dropped ;",
            "DO[105:OFF:Ack2]=PULSE,0.5sec ;",
            '$WAITTMOUT=6000 ;',
            "WAIT DI[105:OFF:Sync2]=OFF TIMEOUT,LBL[409] ;",
            "ENDIF ;",
            "ENDIF ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 408/4501 - TI Ready Timeout ;",
            "LBL[408] ;",
            "R[80]=408 ;",
            "R[90]=4501 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[TI READY TIMEOUT] ;",
            "UALM[94] ;",
            "END ;",
            " ;",
            "--eg:ERR 409/4502 - TI Sync2 Stuck On ;",
            "LBL[409] ;",
            "R[80]=409 ;",
            "R[90]=4502 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[TI SYNC STUCK] ;",
            "UALM[94] ;",
            "END ;",
            " ;",
            "--eg:ERR 502/4503 - TI Unload Subcall Fail ;",
            "LBL[502] ;",
            "R[80]=502 ;",
            "R[90]=4503 ;",
            "MESSAGE[TI UNLOAD FAIL] ;",
            "UALM[94] ;",
            "END ;",
            " ;",
            "--eg:ERR 502/4504 - TI Load Subcall Fail ;",
            "LBL[503] ;",
            "R[80]=502 ;",
            "R[90]=4504 ;",
            "MESSAGE[TI LOAD FAIL] ;",
            "UALM[94] ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_OUT"
        Comment = "Outfeed"
        DefaultGroup = $group1
        Bodies = @(
            "--eg:Outfeed owns F65 clear after handoff; R90 4601 Place Fail, 4602 Conveyor Busy ;",
            "R[80]=200 ;",
            "IF (F[65:OFF:PART_2_PRINT]) THEN ;",
            " ;",
            "--eg:Wait conveyor stopped before place ;",
            '$WAITTMOUT=6000 ;',
            "WAIT (F[52:OFF:Conveyor Running]=OFF) TIMEOUT,LBL[408] ;",
            "WAIT .30(sec) ;",
            "--eg:Debounce conveyor stopped before place ;",
            '$WAITTMOUT=6000 ;',
            "WAIT (F[52:OFF:Conveyor Running]=OFF) TIMEOUT,LBL[408] ;",
            " ;",
            "--eg:Regrip for conveyor unless recipe already has conveyor-ready orientation ;",
            "IF (R[107]<>1) THEN ;",
            "R[94]=0 ;",
            "--eg:Call conveyor regrip before placement ;",
            "CALL A_RGP_CVY ;",
            "IF (R[94]<>200),JMP LBL[503] ;",
            "ENDIF ;",
            "R[94]=0 ;",
            " ;",
            "--eg:Place part on conveyor and wait for result contract ;",
            "CALL A_PLACE_CONVEYOR ;",
            "IF (R[94]=200) THEN ;",
            "F[65:OFF:PART_2_PRINT]=(OFF) ;",
            "ELSE ;",
            "R[80]=502 ;",
            "R[90]=4601 ;",
            "MESSAGE[OUTFEED PLACE FAIL] ;",
            "UALM[96] ;",
            "ENDIF ;",
            "ENDIF ;",
            "END ;",
            " ;",
            "--eg:Error Section *************************** ;",
            " ;",
            "--eg:ERR 408/4602 - Conveyor Busy Timeout ;",
            "LBL[408] ;",
            "R[80]=408 ;",
            "R[90]=4602 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[CONVEYOR BUSY] ;",
            "UALM[96] ;",
            "END ;",
            " ;",
            "--eg:ERR 502/4603 - Conveyor Regrip Fail ;",
            "LBL[503] ;",
            "R[80]=502 ;",
            "R[90]=4603 ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "MESSAGE[CONV REGRIP FAIL] ;",
            "UALM[96] ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_DECIDE"
        Comment = "Loop Decide"
        DefaultGroup = $wildcardGroup
        Bodies = @(
            "--eg:Set 204 only when no infeed or WIP remains ;",
            "R[80]=200 ;",
            "--eg:Any active infeed or WIP means keep cycling ;",
            "IF (F[60:OFF:INFEED]),JMP LBL[200] ;",
            "IF (F[59:OFF]),JMP LBL[200] ;",
            "IF (F[61:OFF:PART_4_CNC]),JMP LBL[200] ;",
            "IF (F[62:OFF:PART_IN_CNC]),JMP LBL[200] ;",
            "IF (F[63:OFF:PART_4_INS]),JMP LBL[200] ;",
            "IF (F[64:OFF:PART_IN_INS]),JMP LBL[200] ;",
            "IF (F[65:OFF:PART_2_PRINT]),JMP LBL[200] ;",
            "--eg:No work remains: Finish Work complete ;",
            "R[80]=204 ;",
            "R[90]=204 ;",
            "END ;",
            " ;",
            "--eg:Work Remains **************************** ;",
            "LBL[200] ;",
            "END ;"
        )
    },
    @{
        ProgramName = "A_FAULT"
        Comment = "Fault Cleanup"
        DefaultGroup = $wildcardGroup
        Bodies = @(
            "--eg:Fault cleanup does not clear WIP flags ;",
            "F[60:OFF:INFEED]=(OFF) ;",
            "F[20:OFF:STOP]=(OFF) ;",
            " ;",
            "--eg:Fault cleanup complete ;",
            "END ;"
        )
    }
)

$records = New-Object System.Collections.Generic.List[object]
foreach ($program in $programs) {
    $stackSize = if ($program.ContainsKey("StackSize")) { [int]$program.StackSize } else { 0 }
    $records.Add((Write-FanucProgram -ProgramName $program.ProgramName -Comment $program.Comment -DefaultGroup $program.DefaultGroup -StackSize $stackSize -Bodies $program.Bodies))
}

$activeProgramNames = @($records | ForEach-Object { $_.ProgramName })

function Get-FanucReferencedPrograms {
    param([string]$SourcePath)

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return @()
    }

    $references = New-Object System.Collections.Generic.List[string]
    foreach ($line in (Get-Content -LiteralPath $SourcePath)) {
        $match = [regex]::Match($line, '^\s*\d+:\s*(?!--eg:|!)(?:IF\s*\(.+\),)?\s*(?:CALL|RUN)\s+([A-Z][A-Z0-9_]+)\b', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($match.Success) {
            [void]$references.Add($match.Groups[1].Value.ToUpperInvariant())
        }
    }

    @($references | Sort-Object -Unique)
}

$closure = New-Object System.Collections.Generic.List[string]
$queue = New-Object System.Collections.Generic.Queue[string]
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($activeProgramName in $activeProgramNames) {
    [void]$seen.Add($activeProgramName)
    $queue.Enqueue($activeProgramName)
}

while ($queue.Count -gt 0) {
    $programName = $queue.Dequeue()
    $sourcePath = Join-Path $sourcesDir ($programName + ".LS")
    foreach ($referencedProgramName in Get-FanucReferencedPrograms -SourcePath $sourcePath) {
        if (-not $seen.Add($referencedProgramName)) {
            continue
        }

        [void]$closure.Add($referencedProgramName)
        $referencedSourcePath = Join-Path $sourcesDir ($referencedProgramName + ".LS")
        if (Test-Path -LiteralPath $referencedSourcePath) {
            $queue.Enqueue($referencedProgramName)
        }
    }
}

$dependencyRecords = foreach ($dependencyProgramName in @($closure | Sort-Object)) {
    $sourcePath = Join-Path $sourcesDir ($dependencyProgramName + ".LS")
    $compiledPath = Join-Path $resolvedOutputRoot ("compiled\" + $dependencyProgramName + ".TP")
    $sourceKind = if ($dependencyProgramName -eq "TSKSTATUS" -or $dependencyProgramName -like "K_*") {
        "KAREL_PC"
    } elseif (Test-Path -LiteralPath $sourcePath) {
        "migration-or-existing-generated"
    } else {
        "external-or-controller-resident"
    }

    [ordered]@{
        ProgramName = $dependencyProgramName
        SourcePath = if (Test-Path -LiteralPath $sourcePath) { (Get-Item -LiteralPath $sourcePath).FullName } else { $null }
        CompiledPath = if (Test-Path -LiteralPath $compiledPath) { (Get-Item -LiteralPath $compiledPath).FullName } else { $null }
        SourceKind = $sourceKind
        ActiveProgram = $activeProgramNames -contains $dependencyProgramName
    }
}

$manifestPath = Join-Path $resolvedOutputRoot "a-main-active-greenfield.json"
[ordered]@{
    generatedAt = (Get-Date).ToString("o")
    programCount = $records.Count
    style = "active-greenfield-state-phase-workflow"
    sourceBaseline = "F_MAIN dependency map 20260513-160748"
    replacesCurrentReviewSet = $true
    reviewPackageNote = "Active programs are the greenfield orchestration set. Dependency programs are required for upload/review closure but may come from the temporary migration generator until rewritten."
    programs = @($records.ToArray())
    dependencyPrograms = @($dependencyRecords)
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding ASCII

[pscustomobject]@{
    ProgramName = "A_MAIN"
    ProgramCount = $records.Count
    ManifestPath = (Get-Item -LiteralPath $manifestPath).FullName
    SourcePath = @($records | Where-Object { $_.ProgramName -eq "A_MAIN" } | Select-Object -First 1).SourcePath
    Programs = @($records.ToArray())
}
