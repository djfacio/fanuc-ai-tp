param(
    [string]$SourceRoot = "generated\sources",
    [string]$OutputRoot = "generated",
    [int]$BreadcrumbRegister = 95,
    [string]$AutoHomeProgramName = "A_AUTO_HOME",
    [switch]$PatchSources,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

function Resolve-ProjectPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return $Path
    }

    return Join-Path $projectRoot $Path
}

function Assert-UnderProject {
    param([string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $fullRoot = [System.IO.Path]::GetFullPath($projectRoot)
    if (-not $fullPath.StartsWith($fullRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to touch path outside project root: $fullPath"
    }

    return $fullPath
}

function Get-MotionRecord {
    param(
        [string]$ProgramName,
        [string]$Line
    )

    $match = [regex]::Match($Line, '^\s*(\d+):\s*([JLC])\s+PR\[(\d+)(?::([^\]]+))?\]\s+(.*?);?\s*$', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    [pscustomobject]@{
        ProgramName = $ProgramName
        SourceLineNumber = [int]$match.Groups[1].Value
        MotionType = $match.Groups[2].Value.ToUpperInvariant()
        PositionRegister = [int]$match.Groups[3].Value
        PositionName = $match.Groups[4].Value.Trim()
        MotionTail = $match.Groups[5].Value.Trim()
        RawLine = $Line.TrimEnd()
    }
}

function Get-SafeTargetForPr {
    param([int]$PositionRegister)

    if ($PositionRegister -ge 1 -and $PositionRegister -le 9) {
        return $PositionRegister
    }
    if ($PositionRegister -ge 10 -and $PositionRegister -le 19) {
        return 1
    }
    if ($PositionRegister -ge 20 -and $PositionRegister -le 39) {
        return 3
    }
    if ($PositionRegister -ge 40 -and $PositionRegister -le 59) {
        return 6
    }
    if ($PositionRegister -ge 60 -and $PositionRegister -le 79) {
        return 7
    }
    if ($PositionRegister -ge 80 -and $PositionRegister -le 109) {
        return 8
    }

    return 1
}

function Get-FrameToolForSafeTarget {
    param([int]$PositionRegister)

    switch ($PositionRegister) {
        1 { return @{ Frame = 0; Tool = 2 } }
        3 { return @{ Frame = 0; Tool = 1 } }
        4 { return @{ Frame = 0; Tool = 1 } }
        5 { return @{ Frame = 0; Tool = 1 } }
        6 { return @{ Frame = 0; Tool = 1 } }
        7 { return @{ Frame = 0; Tool = 1 } }
        8 { return @{ Frame = 5; Tool = 2 } }
        default { return @{ Frame = 0; Tool = 1 } }
    }
}

function Get-AutoHomeRouteForSafeTarget {
    param([int]$PositionRegister)

    switch ($PositionRegister) {
        1 { return @(1) }
        3 { return @(3, 1) }
        4 { return @(4, 6, 1) }
        5 { return @(5, 4, 6, 1) }
        6 { return @(6, 1) }
        7 { return @(7, 1) }
        8 { return @(8, 1) }
        default { return @(1) }
    }
}

function Get-PositionNameForPr {
    param(
        [object[]]$Records,
        [int]$PositionRegister
    )

    $name = @(
        $Records |
            Where-Object { $_.PositionRegister -eq $PositionRegister -and $_.PositionName } |
            Select-Object -ExpandProperty PositionName -Unique |
            Select-Object -First 1
    )

    if ($name.Count -gt 0) {
        return [string]$name[0]
    }

    switch ($PositionRegister) {
        1 { return "JHOME" }
        3 { return "JRGSAFE" }
        4 { return "JSWING_IN" }
        5 { return "JINSIDE" }
        6 { return "JOUTSIDECNC" }
        7 { return "JTISAFE" }
        8 { return "JCONVSAFE" }
        default { return "" }
    }
}

function Format-PrOperand {
    param(
        [object[]]$Records,
        [int]$PositionRegister
    )

    $name = Get-PositionNameForPr -Records $Records -PositionRegister $PositionRegister
    if ($name) {
        return "PR[$PositionRegister`:$name]"
    }

    return "PR[$PositionRegister]"
}

function Get-LinearMmPerSec {
    param([string]$MotionTail)

    $match = [regex]::Match($MotionTail, '(?i)\b([0-9]+(?:\.[0-9]+)?)\s*mm/sec\b')
    if (-not $match.Success) {
        return $null
    }

    return [double]$match.Groups[1].Value
}

function Get-RecoveryMoveSpec {
    param(
        [object[]]$Records,
        [int]$PositionRegister
    )

    $linearSpeeds = @(
        $Records |
            Where-Object { $_.PositionRegister -eq $PositionRegister -and $_.MotionType -eq "L" } |
            ForEach-Object { Get-LinearMmPerSec -MotionTail $_.MotionTail } |
            Where-Object { $null -ne $_ -and $_ -gt 0 }
    )

    if ($linearSpeeds.Count -gt 0) {
        $slowestSourceSpeed = [double](@($linearSpeeds | Sort-Object)[0])
        $recoverySpeed = [Math]::Max(1, [int][Math]::Round($slowestSourceSpeed * 0.10, [System.MidpointRounding]::AwayFromZero))
        return [pscustomobject]@{
            MotionType = "L"
            Speed = "$recoverySpeed`mm/sec"
            SourceSpeed = "$slowestSourceSpeed`mm/sec"
            Rule = "linear-10-percent-source-speed"
        }
    }

    return [pscustomobject]@{
        MotionType = "J"
        Speed = "10%"
        SourceSpeed = ""
        Rule = "joint-10-percent"
    }
}

function Add-SafeMoveBody {
    param(
        [System.Collections.Generic.List[string]]$Bodies,
        [object[]]$Records,
        [int]$PositionRegister
    )

    $frameTool = Get-FrameToolForSafeTarget -PositionRegister $PositionRegister
    $prOperand = Format-PrOperand -Records $Records -PositionRegister $PositionRegister
    $moveSpec = Get-RecoveryMoveSpec -Records $Records -PositionRegister $PositionRegister
    $Bodies.Add("UFRAME_NUM=$($frameTool.Frame) ;")
    $Bodies.Add("UTOOL_NUM=$($frameTool.Tool) ;")
    $Bodies.Add("$($moveSpec.MotionType) $prOperand $($moveSpec.Speed) FINE ;")
}

function Add-BreadcrumbMoveBody {
    param(
        [System.Collections.Generic.List[string]]$Bodies,
        [object[]]$Records,
        [int]$PositionRegister,
        [int]$BreadcrumbRegister
    )

    Add-SafeMoveBody -Bodies $Bodies -Records $Records -PositionRegister $PositionRegister
    $Bodies.Add("R[${BreadcrumbRegister}:Last Motion PR]=$PositionRegister ;")
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

function Format-FanucLsText {
    param([string[]]$Lines)

    $formatted = New-Object System.Collections.Generic.List[string]
    $inMn = $false
    $mnLineNumber = 1
    $lineCount = 0

    foreach ($rawLine in $Lines) {
        $line = [string]$rawLine
        if ($line -match '^\s*/MN\s*$') {
            $inMn = $true
            $formatted.Add($line)
            continue
        }

        if ($line -match '^\s*/POS\s*$') {
            $inMn = $false
            $formatted.Add($line)
            continue
        }

        if (-not $inMn) {
            $formatted.Add($line)
            continue
        }

        if ($line -match '^\s*:\s*(.*)$') {
            $formatted.Add(("    :  {0}" -f $Matches[1]))
            continue
        }

        $body = [regex]::Replace($line, '^\s*\d+\s*:\s*', '')
        $formatted.Add((" {0,3}:  {1}" -f $mnLineNumber, $body.TrimStart()))
        $mnLineNumber++
        $lineCount++
    }

    $text = ($formatted.ToArray() -join "`r`n")
    $text = [regex]::Replace($text, '(?im)^LINE_COUNT\s*=\s*\d+\s*;', "LINE_COUNT`t= $lineCount;")
    return $text
}

$resolvedSourceRoot = Resolve-ProjectPath $SourceRoot
$resolvedOutputRoot = Resolve-ProjectPath $OutputRoot
$sourcesDir = Join-Path $resolvedOutputRoot "sources"
$jobsDir = Join-Path $resolvedOutputRoot "jobs"

foreach ($path in @($resolvedSourceRoot, $resolvedOutputRoot, $sourcesDir, $jobsDir)) {
    Assert-UnderProject $path | Out-Null
}

if (-not (Test-Path -LiteralPath $resolvedSourceRoot)) {
    throw "Source root not found: $resolvedSourceRoot"
}

foreach ($path in @($resolvedOutputRoot, $sourcesDir, $jobsDir)) {
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

$sourceFiles = @(
    Get-ChildItem -LiteralPath $resolvedSourceRoot -Filter "A_*.LS" -File |
        Where-Object { $_.BaseName.ToUpperInvariant() -ne $AutoHomeProgramName.ToUpperInvariant() } |
        Sort-Object Name
)

$motionRecords = New-Object System.Collections.Generic.List[object]
$patchedFiles = New-Object System.Collections.Generic.List[object]

foreach ($file in $sourceFiles) {
    $programName = $file.BaseName.ToUpperInvariant()
    $lines = @(Get-Content -LiteralPath $file.FullName)
    $newLines = New-Object System.Collections.Generic.List[string]
    $inserted = 0
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = [string]$lines[$i]
        $newLines.Add($line)

        $record = Get-MotionRecord -ProgramName $programName -Line $line
        if ($null -eq $record) {
            continue
        }

        $nextLine = if ($i + 1 -lt $lines.Count) { [string]$lines[$i + 1] } else { "" }
        $alreadyPatched = [regex]::IsMatch($nextLine, "^\s*(?:\d+:\s*)?R\[$BreadcrumbRegister(?:[:\]][^\]]*)?\]\s*=\s*$($record.PositionRegister)\s*;", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if (-not $alreadyPatched) {
            $newLines.Add("      R[${BreadcrumbRegister}:Last Motion PR]=$($record.PositionRegister)    ;")
            $inserted++
        }

        $record | Add-Member -NotePropertyName SafeTargetPr -NotePropertyValue (Get-SafeTargetForPr -PositionRegister $record.PositionRegister)
        $motionRecords.Add($record)
    }

    if ($PatchSources -and $inserted -gt 0) {
        if (-not $Force) {
            throw "Would patch $($file.FullName). Use -Force with -PatchSources to overwrite generated sources."
        }

        $content = (Format-FanucLsText -Lines $newLines.ToArray()).TrimEnd() + "`r`n"
        [System.IO.File]::WriteAllText($file.FullName, $content, [System.Text.Encoding]::ASCII)

        $jobDir = Join-Path $jobsDir $programName
        $jobSource = Join-Path $jobDir ($programName + ".LS")
        if (Test-Path -LiteralPath $jobSource) {
            [System.IO.File]::WriteAllText($jobSource, $content, [System.Text.Encoding]::ASCII)
        }
    }

    if ($inserted -gt 0) {
        $patchedFiles.Add([pscustomobject]@{
            ProgramName = $programName
            SourcePath = $file.FullName
            BreadcrumbsInserted = $inserted
        })
    }
}

$records = @($motionRecords.ToArray())
$cntRecords = @($records | Where-Object { $_.MotionTail -match '(?i)\bCNT\d*\b' })
$autoHomeRouteMovePrs = @(11, 21, 31, 42, 51, 61, 62, 71, 81, 91, 101, 5, 4, 6, 3, 7, 8, 1)
$linearRecoveryTargets = @(
    $autoHomeRouteMovePrs |
        Select-Object -Unique |
        ForEach-Object {
            $positionRegister = [int]$_
            $spec = Get-RecoveryMoveSpec -Records $records -PositionRegister $positionRegister
            if ($spec.MotionType -eq "L") {
                [pscustomobject]@{
                    PositionRegister = $positionRegister
                    PositionName = Get-PositionNameForPr -Records $records -PositionRegister $positionRegister
                    RecoverySpeed = $spec.Speed
                    SlowestSourceSpeed = $spec.SourceSpeed
                }
            }
        } |
        Where-Object { $null -ne $_ } |
        Sort-Object PositionRegister
)
$groupedTargets = @($records | Sort-Object SafeTargetPr, PositionRegister, ProgramName, SourceLineNumber | Group-Object SafeTargetPr)

$bodies = New-Object System.Collections.Generic.List[string]
$bodies.Add("OVERRIDE=10% ;")
$bodies.Add("WAIT .10(sec) ;")
$bodies.Add("--eg:Override forced to 10 percent before route selection or motion ;")
$bodies.Add("--eg:Draft auto-home from R[$BreadcrumbRegister] Last Motion PR. Review path on TP before use ;")
$bodies.Add("--eg:Breadcrumb is written after completed motion; mid-motion stops need pendant judgment ;")
$bodies.Add(" ;")
$bodies.Add("--eg:Jump to breadcrumb label, then follow remaining safe route ;")

if ($records.Count -eq 0) {
    throw "No motion records found; cannot generate auto-home dispatch."
}

$bodies.Add("IF R[${BreadcrumbRegister}:Last Motion PR]<1,JMP LBL[900] ;")
$bodies.Add("IF R[${BreadcrumbRegister}:Last Motion PR]>101,JMP LBL[900] ;")
$bodies.Add("IF R[${BreadcrumbRegister}:Last Motion PR]=2,JMP LBL[900] ;")
$bodies.Add("IF R[${BreadcrumbRegister}:Last Motion PR]=9,JMP LBL[900] ;")
$bodies.Add("JMP LBL[R[$BreadcrumbRegister]] ;")

function Add-FallthroughRoute {
    param(
        [System.Collections.Generic.List[string]]$Bodies,
        [object[]]$Records,
        [int[]]$EntryLabels,
        [int[]]$MovePrs,
        [int]$BreadcrumbRegister,
        [string]$Remark,
        [int]$ExitLabel
    )

    $Bodies.Add(" ;")
    $Bodies.Add("--eg:$Remark ;")
    foreach ($label in $EntryLabels) {
        $Bodies.Add("LBL[$label] ;")
    }
    foreach ($movePr in $MovePrs) {
        if ($EntryLabels -notcontains $movePr) {
            $Bodies.Add("LBL[$movePr] ;")
        }
        Add-BreadcrumbMoveBody -Bodies $Bodies -Records $Records -PositionRegister $movePr -BreadcrumbRegister $BreadcrumbRegister
    }
    $Bodies.Add("JMP LBL[$ExitLabel] ;")
}

Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(10, 11) -MovePrs @(11) -BreadcrumbRegister $BreadcrumbRegister -Remark "Bowl pick route: approach then JHOME" -ExitLabel 1
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(20, 21) -MovePrs @(21) -BreadcrumbRegister $BreadcrumbRegister -Remark "Regrip place route: approach then JRGSAFE" -ExitLabel 3
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(30, 31) -MovePrs @(31) -BreadcrumbRegister $BreadcrumbRegister -Remark "Regrip pick route: approach then JRGSAFE" -ExitLabel 3
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(40, 41) -MovePrs @(42) -BreadcrumbRegister $BreadcrumbRegister -Remark "Unload CNC route: safe point then CNC exit" -ExitLabel 6
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(50, 51) -MovePrs @(51) -BreadcrumbRegister $BreadcrumbRegister -Remark "Load CNC route: approach then CNC exit" -ExitLabel 6
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(60, 61) -MovePrs @(61, 62) -BreadcrumbRegister $BreadcrumbRegister -Remark "Unload TI route: approach and safe point" -ExitLabel 7
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(70, 71) -MovePrs @(71) -BreadcrumbRegister $BreadcrumbRegister -Remark "Load TI route: approach then TI safe" -ExitLabel 7
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(80, 81) -MovePrs @(81) -BreadcrumbRegister $BreadcrumbRegister -Remark "Regrip conveyor route: approach then conveyor safe" -ExitLabel 8
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(90, 91) -MovePrs @(91) -BreadcrumbRegister $BreadcrumbRegister -Remark "Temp conveyor route: approach then conveyor safe" -ExitLabel 8
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(100, 101) -MovePrs @(101) -BreadcrumbRegister $BreadcrumbRegister -Remark "Place conveyor route: approach then conveyor safe" -ExitLabel 8
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(5) -MovePrs @(5, 4, 6) -BreadcrumbRegister $BreadcrumbRegister -Remark "Inside CNC route: inside, swing, outside" -ExitLabel 1
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(3) -MovePrs @(3) -BreadcrumbRegister $BreadcrumbRegister -Remark "Regrip safe route then JHOME" -ExitLabel 1
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(7) -MovePrs @(7) -BreadcrumbRegister $BreadcrumbRegister -Remark "Tube insertion safe route then JHOME" -ExitLabel 1
Add-FallthroughRoute -Bodies $bodies -Records $records -EntryLabels @(8) -MovePrs @(8) -BreadcrumbRegister $BreadcrumbRegister -Remark "Conveyor safe route then JHOME" -ExitLabel 1

$bodies.Add(" ;")
$bodies.Add("--eg:Shared final home move ;")
$bodies.Add("LBL[1] ;")
Add-BreadcrumbMoveBody -Bodies $bodies -Records $records -PositionRegister 1 -BreadcrumbRegister $BreadcrumbRegister
$bodies.Add("END ;")

$bodies.Add(" ;")
$bodies.Add("--eg:No matching breadcrumb: do not move automatically ;")
$bodies.Add("LBL[900] ;")
$bodies.Add("MESSAGE[AUTO HOME REVIEW R95] ;")
$bodies.Add("!AUTO HOME REVIEW R95 ;")
$bodies.Add("UALM[16] ;")
$bodies.Add("END ;")

$autoHomeText = New-FanucLsText -ProgramName $AutoHomeProgramName -Comment "Auto Home Draft" -DefaultGroup "1,*,*,*,*,*,*,*" -Bodies $bodies.ToArray()
$autoHomeText = ($autoHomeText -replace "\r?\n", "`r`n").TrimEnd() + "`r`n"
$autoHomePath = Join-Path $sourcesDir ($AutoHomeProgramName + ".LS")
$autoHomeJobDir = Join-Path $jobsDir $AutoHomeProgramName
$autoHomeJobPath = Join-Path $autoHomeJobDir ($AutoHomeProgramName + ".LS")
if (-not (Test-Path -LiteralPath $autoHomeJobDir)) {
    New-Item -ItemType Directory -Path $autoHomeJobDir -Force | Out-Null
}
foreach ($path in @($autoHomePath, $autoHomeJobPath)) {
    if ((Test-Path -LiteralPath $path) -and -not $Force) {
        throw "Output already exists: $path. Use -Force to overwrite."
    }
}
[System.IO.File]::WriteAllText($autoHomePath, $autoHomeText, [System.Text.Encoding]::ASCII)
[System.IO.File]::WriteAllText($autoHomeJobPath, $autoHomeText, [System.Text.Encoding]::ASCII)

$mapPath = Join-Path $resolvedOutputRoot "a-main-auto-home-map.json"
$summaryPath = Join-Path $resolvedOutputRoot "a-main-auto-home-map.md"
$map = [ordered]@{
    generatedAt = (Get-Date).ToString("o")
    sourceRoot = (Get-Item -LiteralPath $resolvedSourceRoot).FullName
    breadcrumbRegister = $BreadcrumbRegister
    autoHomeProgramName = $AutoHomeProgramName
    autoHomeSourcePath = (Get-Item -LiteralPath $autoHomePath).FullName
    patchSources = [bool]$PatchSources
    motionStatementCount = $records.Count
    patchedProgramCount = $patchedFiles.Count
    patchedPrograms = @($patchedFiles.ToArray())
    routePolicy = @(
        "Direct dispatch jumps to the breadcrumb label, matching the reviewed F_GO_HOME example pattern.",
        "Routes are ordered fallthrough chains from the last completed PR toward the next safe PR, then shared home landmarks.",
        "Bowl pick PR10/11 returns through PR11 then PR1 JHOME.",
        "Regrip PR20/21 and PR30/31 return through PR21 or PR31, then PR3 JRGSAFE, then PR1 JHOME.",
        "CNC PR40/41/42 and PR50/51 return through their safe/approach PR, then PR6 JOUTSIDECNC, then PR1 JHOME.",
        "Tube insertion PR60/61/62 and PR70/71 return through their approach/safe PRs, then PR7 JTISAFE, then PR1 JHOME.",
        "Conveyor PR80/81, PR90/91, and PR100/101 return through their approach PR, then PR8 JCONVSAFE, then PR1 JHOME.",
        "Zero, out-of-range, PR2, and PR9 breadcrumbs do not move and raise UALM[16]. Other unexpected in-range gaps rely on the native FANUC missing-label alarm under the current compact-code policy."
    )
    limitations = @(
        "A_AUTO_HOME commands OVERRIDE=10% as the first executable instruction, then waits briefly before route selection.",
        "Dispatch uses JMP LBL[R[$BreadcrumbRegister]] after minimal route validity checks, matching the reviewed F_GO_HOME example shape.",
        "Routes reuse common labels with ordered fallthrough chains, not a synthetic full PR-family alias table.",
        "Breadcrumb writes occur immediately after motion statements.",
        "Auto-home route motions use FINE termination.",
        "Approach/action PRs with reviewed linear source motion back out with L motion at 10 percent of the slowest reviewed source mm/sec speed.",
        "Safe/perch/joint-family landmarks without reviewed linear source motion use J motion at 10 percent.",
        "With CNT source motion, R[$BreadcrumbRegister] may be written before the robot physically reaches the PR; it is route progress, not a pose proof.",
        "Route-chain auto-home intentionally backs up through previous/route-safe points when CNT advance-run makes the breadcrumb ahead of the physical posture.",
        "Breadcrumb source contains $($cntRecords.Count) CNT motion statements; current project policy records these as nonblocking because the cell owner uses Constant Path behavior and owns robot-side route review before commissioning.",
        "Homing routes must not release parts unless a route-level WIP policy explicitly approves the gripper/vacuum/clamp/output action.",
        "The generated route can support automatic HMI-started recovery only after the cell owner approves the route and start conditions.",
        "Routes are inferred from current PR numbering families and must be reviewed by the cell owner."
    )
    cntBreadcrumbMotionCount = $cntRecords.Count
    cntBreadcrumbMotions = @($cntRecords | Select-Object ProgramName, SourceLineNumber, PositionRegister, PositionName, MotionTail)
    linearRecoveryTargets = @($linearRecoveryTargets)
    motionRecords = @($records)
} 
$map | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $mapPath -Encoding ASCII

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# A_MAIN Auto-Home Draft Map")
$lines.Add("")
$lines.Add(("- Breadcrumb register: R[{0}]" -f $BreadcrumbRegister))
$lines.Add("- Motion statements mapped: $($records.Count)")
$lines.Add("- CNT breadcrumb source motions: $($cntRecords.Count)")
$lines.Add("- Linear recovery targets: $($linearRecoveryTargets.Count)")
$lines.Add("- Patched programs: $($patchedFiles.Count)")
$lines.Add(("- Auto-home source: generated/sources/{0}.LS" -f $AutoHomeProgramName))
$lines.Add("")
$lines.Add("## Route Policy")
foreach ($item in $map.routePolicy) {
    $lines.Add("- $item")
}
$lines.Add("")
$lines.Add("## Limitations")
foreach ($item in $map.limitations) {
    $lines.Add("- $item")
}
$lines.Add("")
$lines.Add("## Recovery Motion Speeds")
if ($linearRecoveryTargets.Count -eq 0) {
    $lines.Add("- No linear recovery targets detected.")
} else {
    foreach ($target in $linearRecoveryTargets) {
        $name = if ($target.PositionName) { ":$($target.PositionName)" } else { "" }
        $lines.Add(("- PR[{0}{1}]: L {2} FINE from slowest reviewed source {3}" -f $target.PositionRegister, $name, $target.RecoverySpeed, $target.SlowestSourceSpeed))
    }
}
$lines.Add("")
$lines.Add("## Motion Records")
foreach ($record in @($records | Sort-Object ProgramName, SourceLineNumber)) {
    $name = if ($record.PositionName) { ":$($record.PositionName)" } else { "" }
    $lines.Add(("- {0} line {1}: {2} PR[{3}{4}] -> breadcrumb {3}, safe target PR[{5}]" -f $record.ProgramName, $record.SourceLineNumber, $record.MotionType, $record.PositionRegister, $name, $record.SafeTargetPr))
}
$lines | Set-Content -LiteralPath $summaryPath -Encoding ASCII

[pscustomobject]@{
    BreadcrumbRegister = $BreadcrumbRegister
    MotionStatementCount = $records.Count
    PatchedProgramCount = $patchedFiles.Count
    AutoHomePath = (Get-Item -LiteralPath $autoHomePath).FullName
    MapPath = (Get-Item -LiteralPath $mapPath).FullName
    SummaryPath = (Get-Item -LiteralPath $summaryPath).FullName
}
