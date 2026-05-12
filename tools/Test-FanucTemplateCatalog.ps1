param(
    [string]$CatalogPath = "..\config\template-catalog.psd1",
    [switch]$Quiet
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

if ([System.IO.Path]::IsPathRooted($CatalogPath)) {
    $resolvedCatalog = Resolve-Path -LiteralPath $CatalogPath
} else {
    $resolvedCatalog = Resolve-Path -LiteralPath (Join-Path $scriptRoot $CatalogPath)
}
$resolvedCatalogPath = $resolvedCatalog.Path

$catalog = Import-PowerShellDataFile -LiteralPath $resolvedCatalogPath
$findings = New-Object System.Collections.Generic.List[object]

function Add-Finding {
    param(
        [string]$Rule,
        [string]$Message
    )

    $findings.Add([pscustomobject]@{
        Rule = $Rule
        Message = $Message
    })
}

if ($null -eq $catalog.SchemaVersion -or [int]$catalog.SchemaVersion -ne 1) {
    Add-Finding -Rule "SchemaVersionInvalid" -Message "SchemaVersion must be 1."
}

$ids = @{}
$programs = @{}
$allExampleSpecs = @(Get-ChildItem -LiteralPath (Join-Path $projectRoot "examples") -Filter "*.program-spec.json" | ForEach-Object { $_.FullName })
$catalogExampleSpecs = @{}

foreach ($template in @($catalog.Templates)) {
    if ($null -eq $template) {
        continue
    }

    if (-not $template.Id -or $template.Id -notmatch '^[a-z][a-z0-9-]*$') {
        Add-Finding -Rule "TemplateIdInvalid" -Message "Template Id '$($template.Id)' must be lowercase kebab-case."
    } elseif ($ids.ContainsKey($template.Id)) {
        Add-Finding -Rule "TemplateIdDuplicate" -Message "Template Id '$($template.Id)' appears more than once."
    } else {
        $ids[$template.Id] = $true
    }

    if (-not $template.ProgramName -or $template.ProgramName -cnotmatch '^AI_[A-Z0-9_]{1,29}$') {
        Add-Finding -Rule "ProgramNameInvalid" -Message "Template '$($template.Id)' has invalid ProgramName '$($template.ProgramName)'."
        continue
    }

    if ($programs.ContainsKey($template.ProgramName)) {
        Add-Finding -Rule "ProgramNameDuplicate" -Message "ProgramName '$($template.ProgramName)' appears more than once."
    } else {
        $programs[$template.ProgramName] = $true
    }

    if ($template.MotionClass -notin @("no-motion", "motion-proposed", "motion-reviewed")) {
        Add-Finding -Rule "MotionClassInvalid" -Message "Template '$($template.Id)' has invalid MotionClass '$($template.MotionClass)'."
    }

    if (-not $template.Purpose) {
        Add-Finding -Rule "PurposeMissing" -Message "Template '$($template.Id)' must include Purpose."
    }

    if (@($template.AllowedOperationTypes).Count -lt 1) {
        Add-Finding -Rule "AllowedOperationTypesMissing" -Message "Template '$($template.Id)' must include AllowedOperationTypes."
    }

    if (@($template.Evidence).Count -lt 1) {
        Add-Finding -Rule "EvidenceMissing" -Message "Template '$($template.Id)' must include Evidence."
    }

    $examplePath = Resolve-ProjectPath $template.ExampleSpec
    if (-not (Test-Path -LiteralPath $examplePath)) {
        Add-Finding -Rule "ExampleSpecMissing" -Message "Template '$($template.Id)' example spec '$($template.ExampleSpec)' does not exist."
        continue
    }
    $catalogExampleSpecs[(Get-Item -LiteralPath $examplePath).FullName] = $true

    $spec = Get-Content -LiteralPath $examplePath -Raw | ConvertFrom-Json
    if ($spec.programName -ne $template.ProgramName) {
        Add-Finding -Rule "ExampleProgramMismatch" -Message "Template '$($template.Id)' ProgramName is '$($template.ProgramName)' but example uses '$($spec.programName)'."
    }

    if ($template.MotionClass -eq "no-motion" -and [bool]$spec.safety.motionAllowed) {
        Add-Finding -Rule "NoMotionTemplateAllowsMotion" -Message "Template '$($template.Id)' is no-motion but example allows motion."
    }

    foreach ($operation in @($spec.operations)) {
        if (@($template.AllowedOperationTypes) -notcontains $operation.type) {
            Add-Finding -Rule "OperationNotAllowedByTemplate" -Message "Template '$($template.Id)' example uses operation '$($operation.type)' not listed in AllowedOperationTypes."
        }

        if ($operation.type -eq "registerWrite") {
            $register = "R[$([int]$operation.register)]"
            if (@($template.RegisterWrites) -notcontains $register) {
                Add-Finding -Rule "RegisterWriteNotDeclared" -Message "Template '$($template.Id)' example writes $register but the template does not declare it."
            }
        }

        if ($operation.type -eq "ioWrite") {
            $signal = $operation.signal.ToUpperInvariant()
            if (@($template.IoWrites) -notcontains $signal) {
                Add-Finding -Rule "IoWriteNotDeclared" -Message "Template '$($template.Id)' example writes $signal but the template does not declare it."
            }
        }

        if ($operation.type -eq "callProgram") {
            $target = $operation.program.ToUpperInvariant()
            if (@($template.CallTargets) -notcontains $target) {
                Add-Finding -Rule "CallTargetNotDeclared" -Message "Template '$($template.Id)' example calls $target but the template does not declare it."
            }
        }
    }
}

foreach ($example in $allExampleSpecs) {
    if (-not $catalogExampleSpecs.ContainsKey($example)) {
        Add-Finding -Rule "ExampleSpecUncataloged" -Message "Example spec '$example' is not referenced by the template catalog."
    }
}

$result = New-Object psobject -Property ([ordered]@{
    Path = (Get-Item -LiteralPath $resolvedCatalogPath).FullName
    IsValid = ($findings.Count -eq 0)
    TemplateCount = @($catalog.Templates).Count
    ExampleSpecCount = $allExampleSpecs.Count
    Findings = $findings.ToArray()
})

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "Template catalog validation failed for $($result.Path):`n$($messages -join "`n")"
}
