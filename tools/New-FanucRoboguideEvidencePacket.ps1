param(
    [Parameter(Mandatory = $true)]
    [string]$SpecPath,

    [string]$ConfigPath = "..\config\roboguide-evidence.psd1",
    [string]$CellMapPath = "..\config\cell-map.psd1",
    [string]$OutputPath,
    [switch]$WriteMarkdown,
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

function Resolve-InputPath {
    param([string]$Path)

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    if (Test-Path -LiteralPath $Path) {
        return (Resolve-Path -LiteralPath $Path).Path
    }
    return (Resolve-Path -LiteralPath (Join-Path $scriptRoot $Path)).Path
}

$resolvedSpecPath = Resolve-InputPath -Path $SpecPath
$resolvedConfigPath = Resolve-InputPath -Path $ConfigPath

$configValidator = Join-Path $scriptRoot "Test-FanucRoboguideEvidenceConfig.ps1"
$specValidator = Join-Path $scriptRoot "Test-FanucProgramSpec.ps1"
$motionSpecValidator = Join-Path $scriptRoot "Test-FanucMotionApplicationSpec.ps1"
& $configValidator -ConfigPath $resolvedConfigPath -Quiet

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath
$spec = Get-Content -LiteralPath $resolvedSpecPath -Raw | ConvertFrom-Json
$isMotionApplicationSpec = ($null -ne $spec.motionPlan -and $null -ne $spec.resources -and $null -ne $spec.evidence -and $null -ne $spec.generation)

if ($isMotionApplicationSpec) {
    & $motionSpecValidator -SpecPath $resolvedSpecPath -CellMapPath $CellMapPath -Quiet
} else {
    & $specValidator -SpecPath $resolvedSpecPath -Quiet
}

$program = $spec.programName.ToUpperInvariant()

$operations = if ($isMotionApplicationSpec) { @() } else { @($spec.operations) }
$hasIoWrites = @($operations | Where-Object { $_.type -eq "ioWrite" }).Count -gt 0
$evidenceClass = if ($isMotionApplicationSpec -or [bool]$spec.safety.motionAllowed) {
    "motion"
} elseif ($hasIoWrites) {
    "io-sequence"
} else {
    "no-motion"
}
$policy = @($config.EvidenceClasses | Where-Object { $_.Name -eq $evidenceClass } | Select-Object -First 1)

if (-not $OutputPath) {
    $OutputPath = "generated\jobs\$program\roboguide-evidence-packet.json"
}
$resolvedOutputPath = Resolve-ProjectPath $OutputPath
if ((Test-Path -LiteralPath $resolvedOutputPath) -and -not $Force) {
    throw "RoboGuide evidence packet already exists: $resolvedOutputPath. Use -Force to overwrite."
}

$registerWrites = @($operations | Where-Object { $_.type -eq "registerWrite" } | ForEach-Object {
    [ordered]@{
        register = "R[$([int]$_.register)]"
        value = [int]$_.value
    }
})
$ioWrites = @($operations | Where-Object { $_.type -eq "ioWrite" } | ForEach-Object {
    [ordered]@{
        signal = $_.signal.ToUpperInvariant()
        state = if ([bool]$_.state) { "ON" } else { "OFF" }
    }
})

$motionResources = $null
$motionSequence = @()
if ($isMotionApplicationSpec) {
    $motionResources = [ordered]@{
        userFrame = [ordered]@{
            number = [int]$spec.resources.userFrame.number
            name = $spec.resources.userFrame.name
            source = $spec.resources.userFrame.source
            verified = [bool]$spec.resources.userFrame.verified
        }
        userTool = [ordered]@{
            number = [int]$spec.resources.userTool.number
            name = $spec.resources.userTool.name
            source = $spec.resources.userTool.source
            verified = [bool]$spec.resources.userTool.verified
        }
        payload = [ordered]@{
            number = [int]$spec.resources.payload.number
            name = $spec.resources.payload.name
            source = $spec.resources.payload.source
            verified = [bool]$spec.resources.payload.verified
        }
        points = @($spec.resources.points | ForEach-Object {
            [ordered]@{
                name = $_.name
                source = $_.source
                verified = [bool]$_.verified
                touchupRequired = [bool]$_.touchupRequired
            }
        })
    }

    $motionSequence = @($spec.motionPlan.motionSequence | ForEach-Object {
        $termination = if ($_.termination.type -eq "CNT") { "CNT$([int]$_.termination.value)" } else { "FINE" }
        [ordered]@{
            stepName = $_.stepName
            motionType = $_.motionType
            target = "PR[$([int]$_.target.number)]"
            targetName = $_.target.name
            targetSource = $_.target.source
            targetVerified = [bool]$_.target.verified
            speed = "$($_.speed.value)$($_.speed.unit)"
            termination = $termination
            expectedLs = "$($_.motionType) PR[$([int]$_.target.number)] $($_.speed.value)$($_.speed.unit) $termination"
        }
    })
}

$steps = New-Object System.Collections.Generic.List[object]
$stepNumber = 1
$steps.Add([ordered]@{ step = $stepNumber++; name = "Open workcell"; expected = "Intended RoboGuide workcell is open and controller version is reviewed." })
$steps.Add([ordered]@{ step = $stepNumber++; name = "Load program"; expected = "$program.TP is loaded or present on the virtual controller." })
$motionAllowedText = if ($isMotionApplicationSpec) { "reviewed motion application" } else { "MotionAllowed=$($spec.safety.motionAllowed)" }
$steps.Add([ordered]@{ step = $stepNumber++; name = "Review safety"; expected = "$motionAllowedText; human review is complete before running." })
if ($isMotionApplicationSpec) {
    $steps.Add([ordered]@{ step = $stepNumber++; name = "Review frame/tool/payload"; expected = "UFRAME=$($spec.resources.userFrame.number) '$($spec.resources.userFrame.name)', UTOOL=$($spec.resources.userTool.number) '$($spec.resources.userTool.name)', PAYLOAD=$($spec.resources.payload.number) '$($spec.resources.payload.name)' match the virtual controller." })
    $steps.Add([ordered]@{ step = $stepNumber++; name = "Review PR targets"; expected = "Each PR target in the motion sequence is present, touched up or verified, and matches the documented source." })
    $steps.Add([ordered]@{ step = $stepNumber++; name = "Review path"; expected = "Step through the PR waypoint sequence at reduced override and verify clearance, approach, work, retract, and recovery assumptions." })
}
if ([bool]$policy.RequiresBeforeAfterSnapshot) {
    $steps.Add([ordered]@{ step = $stepNumber++; name = "Capture before snapshot"; expected = "Record relevant registers, IO, frames/tools, and mode before execution." })
}
$steps.Add([ordered]@{ step = $stepNumber++; name = "Execute or inspect"; expected = "Run in RoboGuide when useful, or inspect in controlled manual mode for no-motion programs." })
if ([bool]$policy.RequiresBeforeAfterSnapshot) {
    $steps.Add([ordered]@{ step = $stepNumber++; name = "Capture after snapshot"; expected = "Record relevant registers, IO, frames/tools, and mode after execution." })
}
$steps.Add([ordered]@{ step = $stepNumber++; name = "Record result"; expected = "Record passed/failed/not-required, reviewer, date, and notes." })

$packet = [ordered]@{
    schemaVersion = 1
    generatedAt = (Get-Date).ToString("o")
    programName = $program
    specPath = (Get-Item -LiteralPath $resolvedSpecPath).FullName
    evidenceClass = $evidenceClass
    roboguideRequired = [bool]$policy.RoboguideRequired
    operatorRunDecisionOwned = [bool]$policy.OperatorRunDecisionOwned
    requiresBeforeAfterSnapshot = [bool]$policy.RequiresBeforeAfterSnapshot
    requiredSections = @($policy.RequiredSections)
    intent = if ($isMotionApplicationSpec) { $spec.purpose } else { $spec.intent }
    specType = if ($isMotionApplicationSpec) { "motion-application" } else { "program" }
    safety = $spec.safety
    motionResources = $motionResources
    motionPlan = if ($isMotionApplicationSpec) {
        [ordered]@{
            motionTypes = @($spec.motionPlan.motionTypes)
            speedPolicy = $spec.motionPlan.speedPolicy
            terminationPolicy = $spec.motionPlan.terminationPolicy
            approachRetract = $spec.motionPlan.approachRetract
            clearancePolicy = $spec.motionPlan.clearancePolicy
            recoveryPlan = $spec.motionPlan.recoveryPlan
            sequence = @($motionSequence)
        }
    } else {
        $null
    }
    expectedWrites = [ordered]@{
        registers = $registerWrites
        ioSignals = $ioWrites
    }
    steps = @($steps.ToArray())
    result = [ordered]@{
        status = "pending"
        reviewer = ""
        date = ""
        workcellPath = ""
        notes = ""
    }
}

$outputDir = Split-Path -Parent $resolvedOutputPath
if (-not (Test-Path -LiteralPath $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}
$packet | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedOutputPath -Encoding ASCII

$markdownPath = $null
if ($WriteMarkdown) {
    $markdownPath = [System.IO.Path]::ChangeExtension($resolvedOutputPath, ".md")
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# RoboGuide Evidence Packet: $program")
    $lines.Add("")
    $lines.Add("- Evidence class: $evidenceClass")
    $lines.Add("- Spec type: $(if ($isMotionApplicationSpec) { "motion-application" } else { "program" })")
    $lines.Add("- RoboGuide evidence gate: $([bool]$policy.RoboguideRequired)")
    $lines.Add("- Operator run decision owned: $([bool]$policy.OperatorRunDecisionOwned)")
    $lines.Add("- Before/after snapshot gate: $([bool]$policy.RequiresBeforeAfterSnapshot)")
    $lines.Add("")
    $lines.Add("## Intent")
    $lines.Add("")
    $lines.Add($(if ($isMotionApplicationSpec) { $spec.purpose } else { $spec.intent }))
    $lines.Add("")
    if ($isMotionApplicationSpec) {
        $lines.Add("## Motion Resources")
        $lines.Add("")
        $lines.Add("- UFRAME[$($spec.resources.userFrame.number)]: $($spec.resources.userFrame.name) - verified=$([bool]$spec.resources.userFrame.verified)")
        $lines.Add("- UTOOL[$($spec.resources.userTool.number)]: $($spec.resources.userTool.name) - verified=$([bool]$spec.resources.userTool.verified)")
        $lines.Add("- PAYLOAD[$($spec.resources.payload.number)]: $($spec.resources.payload.name) - verified=$([bool]$spec.resources.payload.verified)")
        $lines.Add("")
        $lines.Add("## Motion Sequence")
        $lines.Add("")
        foreach ($move in @($motionSequence)) {
            $lines.Add("- $($move.stepName): $($move.expectedLs) ; source=$($move.targetSource); verified=$($move.targetVerified)")
        }
        $lines.Add("")
        $lines.Add("## Motion Review")
        $lines.Add("")
        $lines.Add("- Speed policy: $($spec.motionPlan.speedPolicy)")
        $lines.Add("- Termination policy: $($spec.motionPlan.terminationPolicy)")
        $lines.Add("- Clearance policy: $($spec.motionPlan.clearancePolicy)")
        $lines.Add("- Recovery plan: $($spec.motionPlan.recoveryPlan)")
        $lines.Add("")
    }
    $lines.Add("## Suggested Sections")
    $lines.Add("")
    foreach ($section in @($policy.RequiredSections)) {
        $lines.Add("- $section")
    }
    $lines.Add("")
    $lines.Add("## Expected Writes")
    $lines.Add("")
    foreach ($write in $registerWrites) {
        $lines.Add("- $($write.register) = $($write.value)")
    }
    foreach ($write in $ioWrites) {
        $lines.Add("- $($write.signal) = $($write.state)")
    }
    if ($registerWrites.Count -eq 0 -and $ioWrites.Count -eq 0) {
        $lines.Add("- none")
    }
    $lines.Add("")
    $lines.Add("## Steps")
    $lines.Add("")
    foreach ($step in @($steps.ToArray())) {
        $lines.Add("$($step.step). $($step.name): $($step.expected)")
    }
    $lines.Add("")
    $lines.Add("## Result")
    $lines.Add("")
    $lines.Add("- Status: pending")
    $lines.Add("- Reviewer:")
    $lines.Add("- Date:")
    $lines.Add("- Workcell:")
    $lines.Add("- Notes:")
    $lines | Set-Content -LiteralPath $markdownPath -Encoding ASCII
}

[pscustomobject]@{
    ProgramName = $program
    EvidenceClass = $evidenceClass
    RoboguideRequired = [bool]$policy.RoboguideRequired
    OperatorRunDecisionOwned = [bool]$policy.OperatorRunDecisionOwned
    RequiresBeforeAfterSnapshot = [bool]$policy.RequiresBeforeAfterSnapshot
    OutputPath = (Get-Item -LiteralPath $resolvedOutputPath).FullName
    MarkdownPath = if ($markdownPath) { (Get-Item -LiteralPath $markdownPath).FullName } else { $null }
}
