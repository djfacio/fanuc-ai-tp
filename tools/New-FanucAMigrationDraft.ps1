param(
    [string]$SourceProgramsRoot = "generated\dependency-map\20260513-160748-F_MAIN\programs",
    [string]$OutputRoot = "generated",
    [switch]$IncludeMain,
    [switch]$Force
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot

if ([System.IO.Path]::IsPathRooted($SourceProgramsRoot)) {
    $resolvedSourceRoot = Resolve-Path -LiteralPath $SourceProgramsRoot
} else {
    $resolvedSourceRoot = Resolve-Path -LiteralPath (Join-Path $projectRoot $SourceProgramsRoot)
}

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

$sourceFiles = @(Get-ChildItem -LiteralPath $resolvedSourceRoot -Directory | ForEach-Object {
    $programName = $_.Name.ToUpperInvariant()
    $lsPath = Join-Path $_.FullName ($programName + ".LS")
    if ($programName -like "F_*" -and (Test-Path -LiteralPath $lsPath)) {
        [pscustomobject]@{
            SourceProgram = $programName
            TargetProgram = "A_" + $programName.Substring(2)
            SourcePath = $lsPath
        }
    }
})

if (-not $IncludeMain) {
    $sourceFiles = @($sourceFiles | Where-Object { $_.SourceProgram -ne "F_MAIN" })
}

$programMap = [ordered]@{}
foreach ($file in $sourceFiles) {
    $programMap[$file.SourceProgram] = $file.TargetProgram
}

function Convert-FanucProgramText {
    param(
        [string]$Text,
        [string]$SourceProgram,
        [string]$TargetProgram,
        [hashtable]$ProgramMap
    )

    $converted = $Text
    $converted = [regex]::Replace($converted, "(?im)^(\s*/PROG\s+)$([regex]::Escape($SourceProgram))(\s*(?:Macro)?\s*)$", "`${1}$TargetProgram`${2}")
    $converted = [regex]::Replace($converted, "(?im)^(COMMENT\s*=\s*)`"[^`"]*`"\s*;", "`${1}`"A MIGRATION DRAFT`";")
    $converted = [regex]::Replace($converted, "(?im)^(FILE_NAME\s*=\s*).+?;", "`${1} ;")
    $converted = [regex]::Replace($converted, "(?im)^(PROG_SIZE\s*=\s*)\d+\s*;", "`${1}0;")
    $converted = [regex]::Replace($converted, "(?im)^(MEMORY_SIZE\s*=\s*)\d+\s*;", "`${1}0;")

    foreach ($sourceName in $ProgramMap.Keys) {
        $targetName = $ProgramMap[$sourceName]
        $converted = [regex]::Replace($converted, "\b(CALL\s+)$([regex]::Escape($sourceName))\b", "`${1}$targetName")
        $converted = [regex]::Replace($converted, "\b(RUN\s+)$([regex]::Escape($sourceName))\b", "`${1}$targetName")
        $converted = $converted -replace "'$([regex]::Escape($sourceName))'", "'$targetName'"
    }

    $converted = $converted -replace "'F_MAIN'", "'A_MAIN'"
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Owned by Cubic Machinery Written by David Facio\s*;', '${1}--eg:Original F_ workflow by David Facio ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Activates Hopper to feed more parts into the FLEXI-LOADER\s*;', '${1}--eg:Feed parts into the Flexi Loader hopper ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Runs parallel to main program, asynchronously manages the\s*\r?\n\s*:\s*FLEXI-LOADER\s*;', '${1}--eg:Async Flexi Loader vision/feed task ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Runs parallel to main program, asynchronously manages the CONVEYOR\s*;', '${1}--eg:Async conveyor task ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:MACRO Opens Tubin Insertion Gripper 2\s*;', '${1}--eg:MACRO opens Tube Insertion Gripper 2 ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Shakes Rattles and Rolls the FLEXI-LOADER\s*;', '${1}--eg:Agitate Flexi Loader bowl ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Unload Part into the Tube Insertion\s*;', '${1}--eg:Unload part from Tube Insertion ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Unload part from the CNC\s*;', '${1}--eg:Unload part from CNC ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Calculate Unload Offset Position\s*;', '${1}--eg:Use reviewed unload position ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)!Wait for the reply\s*;', '${1}--eg:WAIT FOR VISION REPLY ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)!Save result in R50\s*;', '${1}!Save vision result ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)!Save values to R30\.\.\.\s*;', '${1}!Save vision offsets ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)!Wait and set reply to R50\s*;', '${1}--eg:WAIT FOR VISION REPLY ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)!VS_COM_ERROR\s*;', '${1}--eg:FAULT VISION COM ERROR ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)!HOPPER LIMIT REACHED\s*;', '${1}--eg:FAULT HOPPER LIMIT REACHED ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Initializes Vision\s*;', '${1}--eg:Initialize vision interface ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Initializes Registers and IOs\s*;', '${1}--eg:Initialize registers and IO ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:Owned by Cubic Machinery Written by David Facio\s+Pick &\s*\r?\n\s*:\s*Place Part On Regrip Station\s*;', '${1}--eg:Original F_ workflow by David Facio ;' + "`r`n" + '${1}--eg:Regrip pick and place ;')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*)--eg:\s*;', '${1};')
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*!\s*)(?<text>.*?)(?:\s+)?\s*;', {
        param($match)
        $text = ($match.Groups["text"].Value -replace '\s+', ' ').Trim()
        "$($match.Groups[1].Value)$text ;"
    })
    $converted = [regex]::Replace($converted, '(?im)^(\s*\d+:\s*--eg:)(?<text>.*?)(?:\s+)?\s*;', {
        param($match)
        $text = ($match.Groups["text"].Value -replace '\s+', ' ').Trim()
        if ($text.Length -eq 0) {
            "$($match.Groups[1].Value -replace '--eg:$', '') ;"
        } else {
            "$($match.Groups[1].Value)$text ;"
        }
    })

    $hasMotionInstruction = $converted -match '(?im)^\s*\d+:\s*[JLC]\s+'
    $hasPrCalculation = $converted -match '(?im)^\s*\d+:\s*PR\[(?:GP\d+:)?[^\]]+\]\s*='
    if (-not $hasMotionInstruction -and -not $hasPrCalculation) {
        $converted = [regex]::Replace($converted, '(?im)^(DEFAULT_GROUP\s*=\s*)[^;]+;', '${1}*,*,*,*,*,*,*,*;')
    }

    return $converted
}

function Add-FanucMnLinesBeforePos {
    param(
        [string]$Text,
        [string[]]$Bodies
    )

    $matches = [regex]::Matches($Text, '(?m)^\s*(\d+):')
    $nextLine = 1
    foreach ($match in $matches) {
        $line = [int]$match.Groups[1].Value
        if ($line -ge $nextLine) {
            $nextLine = $line + 1
        }
    }

    $newLines = foreach ($body in $Bodies) {
        (" {0,3}:  {1}" -f $nextLine, $body)
        $nextLine++
    }

    $insertText = ($newLines -join "`r`n") + "`r`n"
    $updated = [regex]::Replace($Text, '(?m)^/POS\s*$', ($insertText + "/POS"), 1)
    $lineCount = [regex]::Matches($updated, '(?m)^\s*\d+:').Count
    return [regex]::Replace($updated, '(?im)^(LINE_COUNT\s*=\s*)\d+\s*;', "`${1}$lineCount;")
}

function Convert-FanucKnownWaits {
    param(
        [string]$Text,
        [string]$TargetProgram
    )

    $converted = $Text
    if ($TargetProgram -eq "A_FLEXI_LOADER") {
        $converted = [regex]::Replace(
            $converted,
            "(?im)^(\s*\d+:\s*)CALL F_TASK_STATUS\('A_MAIN',1\)\s*;\s*\r?\n\s*\d+:\s*//IF R\[1:TASK STATUS\]<>0,JMP LBL\[999\]\s*;",
            "`${1}--eg:MAIN 200 CONTINUE, ELSE STOP ;`r`n`${1}CALL TSKSTATUS('A_MAIN',92,0) ;`r`n`${1}IF R[92]<>200,JMP LBL[999] ;"
        )
        $converted = [regex]::Replace(
            $converted,
            "(?im)^(\s*\d+:\s*LBL\[999\]\s*;\s*\r?\n\s*\d+:\s*CALL K_VS_CLOSE\s*;)",
            "`${1}`r`n   999:  END ;"
        )
    }

    if ($TargetProgram -eq "A_UNLOAD_CNC") {
        $converted = [regex]::Replace(
            $converted,
            '(?im)^(\s*\d+:\s*)--eg:Owned by Cubic Machinery Written by David Facio\s*;',
            "`${1}--eg:Owned by Cubic Machinery Written by David Facio ;`r`n`${1}R[94]=0 ;"
        )
        $converted = [regex]::Replace(
            $converted,
            '(?im)^(\s*\d+:\s*)WAIT\s+DI\[106:([^\]]*)\]\s*=\s*OFF\s*;',
            "`${1}`$WAITTMOUT=6000 ;`r`n`${1}WAIT DI[106:`${2}]=OFF TIMEOUT,LBL[406] ;"
        )
        $converted = Add-FanucMnLinesBeforePos -Text $converted -Bodies @(
            "R[94]=200 ;",
            "END ;",
            ";",
            "LBL[406] ;",
            "R[90]=406 ;",
            "R[94]=408 ;",
            "MESSAGE[G1 CLOSE TIMEOUT] ;",
            "UALM[95] ;"
        )
    }

    if ($TargetProgram -in @("A_PICK", "A_REGRIP", "A_RGP_CVY", "A_LOAD_CNC", "A_UNLOAD_TI", "A_LOAD_TI")) {
        $firstOriginalRemark = [regex]::new('(?im)^(\s*\d+:\s*)--eg:Original F_ workflow by David Facio\s*;')
        $converted = $firstOriginalRemark.Replace(
            $converted,
            "`${1}--eg:Original F_ workflow by David Facio ;`r`n`${1}R[94]=0 ;",
            1
        )
        $converted = Add-FanucMnLinesBeforePos -Text $converted -Bodies @(
            "R[94]=200 ;",
            "END ;"
        )
    }

    if ($TargetProgram -eq "A_PLACE_CONVEYOR") {
        $converted = [regex]::Replace(
            $converted,
            '(?im)^(\s*\d+:\s*)--eg:Place Part on Conveyor\s*;',
            "`${1}--eg:Place Part on Conveyor ;`r`n`${1}R[94]=0 ;`r`n`${1}--eg:CONV MUST BE 204/404 BEFORE PLACE ;`r`n`${1}CALL TSKSTATUS('A_CONVEYOR',93,0) ;`r`n`${1}IF (R[93]=204),JMP LBL[425] ;`r`n`${1}IF (R[93]=404),JMP LBL[425] ;`r`n`${1}R[90]=409 ;`r`n`${1}R[94]=409 ;`r`n`${1}MESSAGE[CONV START BLOCKED] ;`r`n`${1}UALM[98] ;`r`n`${1}END ;`r`n`${1}LBL[425] ;"
        )
        $converted = [regex]::Replace(
            $converted,
            '(?im)^(\s*\d+:\s*)RUN\s+A_CONVEYOR\s*;',
            "`${1}--eg:Call conveyor and require proof before return ;`r`n`${1}CALL A_CONVEYOR ;`r`n`${1}IF (R[94]=200),JMP LBL[430] ;`r`n`${1}END ;`r`n`${1}LBL[430] ;"
        )
    }

    if ($TargetProgram -eq "A_CONVEYOR") {
        $converted = [regex]::Replace(
            $converted,
            '(?im)^(\s*\d+:\s*)F\[52:([^\]]*)\]=\(ON\)\s*;',
            "`${1}R[94]=0 ;`r`n`${1}F[52:`${2}]=(ON) ;"
        )
        $converted = [regex]::Replace(
            $converted,
            '(?im)^(\s*\d+:\s*)WAIT\s+DI\[110:([^\]]*)\]\s*=\s*ON\s+TIMEOUT,LBL\[404\]\s*;',
            "`${1}`$WAITTMOUT=6000 ;`r`n`${1}WAIT DI[110:`${2}]=ON TIMEOUT,LBL[404] ;"
        )
        $converted = [regex]::Replace(
            $converted,
            '(?im)^(\s*\d+:\s*)DO\[117:([^\]]*)\]\s*=\s*PULSE,7\.0sec\s*;',
            "`${1}DO[117:`${2}]=ON ;`r`n`${1}WAIT   7.00(sec) ;`r`n`${1}DO[117:`${2}]=OFF ;"
        )
        $converted = [regex]::Replace(
            $converted,
            '(?ims)^(\s*\d+:\s*)LBL\[404\]\s*;\s*\r?\n\s*\d+:\s*F\[52:([^\]]*)\]=\(OFF\)\s*;\s*\r?\n\s*\d+:\s*UALM\[10\]\s*;',
            "`${1}LBL[404] ;`r`n`${1}R[90]=408 ;`r`n`${1}R[94]=408 ;`r`n`${1}DO[117:OFF:Conveyor Foward]=OFF ;`r`n`${1}F[52:`${2}]=(OFF) ;`r`n`${1}MESSAGE[CONV PART TIMEOUT] ;`r`n`${1}UALM[10] ;`r`n`${1}END ;"
        )
        $converted = [regex]::Replace(
            $converted,
            '(?im)^(\s*\d+:\s*)F\[52:([^\]]*)\]=\(OFF\)\s*;\s*\r?\n\s*\d+:\s*END\s*;',
            "`${1}F[52:`${2}]=(OFF) ;`r`n`${1}R[94]=200 ;`r`n`${1}END ;"
        )
    }

    if ($TargetProgram -eq "A_CONV_DROP") {
        $converted = [regex]::Replace(
            $converted,
            '(?im)^(\s*\d+:\s*)WAIT\s+\(F\[52:([^\]]*)\]\s*=\s*OFF\)\s*;',
            "`${1}`$WAITTMOUT=6000 ;`r`n`${1}WAIT (F[52:`${2}]=OFF) TIMEOUT,LBL[452] ;"
        )
        $converted = [regex]::Replace(
            $converted,
            '(?im)^(\s*\d+:\s*)CALL\s+A_PLACE_CONVEYOR\s*;',
            "`${1}R[94]=0 ;`r`n`${1}CALL A_PLACE_CONVEYOR ;`r`n`${1}IF (R[94]=200),JMP LBL[451] ;`r`n`${1}R[90]=500 ;`r`n`${1}MESSAGE[CONV DROP FAILED] ;`r`n`${1}END ;`r`n`${1}LBL[451] ;"
        )
        $converted = Add-FanucMnLinesBeforePos -Text $converted -Bodies @(
            "END ;",
            ";",
            "LBL[452] ;",
            "R[90]=452 ;",
            "MESSAGE[CONV BUSY TIMEOUT] ;",
            "UALM[96] ;"
        )
    }

    if ($TargetProgram -eq "A_INIT") {
        $converted = [regex]::Replace(
            $converted,
            "(?im)^\s*\d+:\s*CALL\s+A_SELECT_VISION\(R\[100:PART NUMBER\]\)\s*;\s*\r?\n",
            ""
        )
        $converted = [regex]::Replace(
            $converted,
            "(?im)^\s*\d+:\s*CALL\s+A_INIT_VISION\s*;\s*\r?\n",
            ""
        )
    }

    return $converted
}

function Convert-FanucMnLineNumbers {
    param([string]$Text)

    $mnMatch = [regex]::Match($Text, '(?s)(?<before>/MN\s*)(?<mn>.*?)(?<after>/POS)')
    if (-not $mnMatch.Success) {
        return $Text
    }

    $lineNumber = 1
    $newMnLines = foreach ($line in ($mnMatch.Groups["mn"].Value -split "`r?`n")) {
        if ($line -match '^\s*\d+:\s*(?<body>.*)$') {
            $body = $Matches["body"]
            (" {0,3}:  {1}" -f $lineNumber, $body)
            $lineNumber++
        } elseif ($line -match '^\s*:\s*(?<body>.*)$') {
            "    :  $($Matches["body"])"
        } elseif ($line.Trim().Length -eq 0) {
            $line
        } else {
            $line
        }
    }

    $lineCount = $lineNumber - 1
    $newMn = ($newMnLines -join "`r`n")
    $updated = $Text.Substring(0, $mnMatch.Index) + $mnMatch.Groups["before"].Value + $newMn + "`r`n" + $mnMatch.Groups["after"].Value + $Text.Substring($mnMatch.Index + $mnMatch.Length)
    return [regex]::Replace($updated, '(?im)^(LINE_COUNT\s*=\s*)\d+\s*;', "`${1}$lineCount;")
}

function Set-FanucStackSize {
    param(
        [string]$Text,
        [int]$StackSize
    )

    return [regex]::Replace($Text, '(?im)^(TCD:\s*STACK_SIZE\s*=\s*)\d+(\s*,)', "`${1}$StackSize`${2}")
}

function Test-FanucNeedsExplicitStackBudget {
    param(
        [string]$Text,
        [string]$TargetProgram
    )

    if ($TargetProgram -in @("A_MAIN", "A_STARTUP", "A_SELECT_VISION", "A_INIT_VISION", "A_FLEXI_LOADER")) {
        return $true
    }

    return ($Text -match '(?im)^\s*\d+:\s*CALL\s+(?:K_|TSKSTATUS\b)')
}

$records = New-Object System.Collections.Generic.List[object]
foreach ($file in $sourceFiles) {
    $text = Get-Content -LiteralPath $file.SourcePath -Raw
    $converted = Convert-FanucProgramText -Text $text -SourceProgram $file.SourceProgram -TargetProgram $file.TargetProgram -ProgramMap $programMap
    $converted = Convert-FanucKnownWaits -Text $converted -TargetProgram $file.TargetProgram
    $converted = Convert-FanucMnLineNumbers -Text $converted
    $stackSize = 0
    if (Test-FanucNeedsExplicitStackBudget -Text $converted -TargetProgram $file.TargetProgram) {
        $stackSize = 1000
        $converted = Set-FanucStackSize -Text $converted -StackSize $stackSize
    }

    $sourceOut = Join-Path $sourcesDir ($file.TargetProgram + ".LS")
    $jobDir = Join-Path $jobsDir $file.TargetProgram
    $jobSourceOut = Join-Path $jobDir ($file.TargetProgram + ".LS")
    if (-not (Test-Path -LiteralPath $jobDir)) {
        New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
    }

    foreach ($path in @($sourceOut, $jobSourceOut)) {
        if ((Test-Path -LiteralPath $path) -and -not $Force) {
            throw "Output already exists: $path. Use -Force to overwrite."
        }
    }

    $converted = ($converted -replace "\r?\n", "`r`n").TrimEnd() + "`r`n"
    $ascii = [System.Text.Encoding]::ASCII
    [System.IO.File]::WriteAllText($sourceOut, $converted, $ascii)
    [System.IO.File]::WriteAllText($jobSourceOut, $converted, $ascii)

    $records.Add([pscustomobject]@{
        SourceProgram = $file.SourceProgram
        TargetProgram = $file.TargetProgram
        SourcePath = (Get-Item -LiteralPath $sourceOut).FullName
        JobSourcePath = (Get-Item -LiteralPath $jobSourceOut).FullName
        StackSize = $stackSize
    })
}

$manifestPath = Join-Path $resolvedOutputRoot "a-migration-draft.json"
[ordered]@{
    generatedAt = (Get-Date).ToString("o")
    sourceProgramsRoot = (Get-Item -LiteralPath $resolvedSourceRoot).FullName
    includeMain = [bool]$IncludeMain.IsPresent
    stackSensitiveHoists = @(
        @{
            programs = @("A_SELECT_VISION", "A_INIT_VISION")
            removedFrom = "A_INIT"
            expectedCaller = "A_STARTUP"
            reason = "KAREL vision bridge helpers are stack-sensitive. Keep generated wrappers, but call them from the startup level instead of behind A_INIT."
        }
    )
    programCount = $records.Count
    programs = @($records.ToArray())
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding ASCII

[pscustomobject]@{
    ProgramCount = $records.Count
    ManifestPath = (Get-Item -LiteralPath $manifestPath).FullName
    Programs = @($records.ToArray())
}
