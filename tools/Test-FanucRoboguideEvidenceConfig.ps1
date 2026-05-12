param(
    [string]$ConfigPath = "..\config\roboguide-evidence.psd1",
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}
$resolvedConfigPath = $resolvedConfig.Path

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfigPath
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

if ($null -eq $config.SchemaVersion -or [int]$config.SchemaVersion -ne 1) {
    Add-Finding -Rule "SchemaVersionInvalid" -Message "SchemaVersion must be 1."
}

$requiredClasses = @("no-motion", "io-sequence", "motion")
$classes = @{}
foreach ($entry in @($config.EvidenceClasses)) {
    if ($null -eq $entry) {
        continue
    }

    if ($entry.Name -notin $requiredClasses) {
        Add-Finding -Rule "EvidenceClassInvalid" -Message "Unexpected evidence class '$($entry.Name)'."
        continue
    }
    if ($classes.ContainsKey($entry.Name)) {
        Add-Finding -Rule "EvidenceClassDuplicate" -Message "Evidence class '$($entry.Name)' appears more than once."
    }
    $classes[$entry.Name] = $true

    foreach ($key in @("RoboguideRequired", "ManualT1Required", "RequiresBeforeAfterSnapshot")) {
        if ($null -eq $entry[$key] -or $entry[$key] -isnot [bool]) {
            Add-Finding -Rule "EvidenceClassBoolInvalid" -Message "$($entry.Name).$key must be true or false."
        }
    }
    if (@($entry.RequiredSections).Count -lt 1) {
        Add-Finding -Rule "RequiredSectionsMissing" -Message "$($entry.Name) must include RequiredSections."
    }
}

foreach ($required in $requiredClasses) {
    if (-not $classes.ContainsKey($required)) {
        Add-Finding -Rule "EvidenceClassMissing" -Message "Evidence class '$required' is required."
    }
}

$result = New-Object psobject -Property ([ordered]@{
    Path = (Get-Item -LiteralPath $resolvedConfigPath).FullName
    IsValid = ($findings.Count -eq 0)
    EvidenceClassCount = @($config.EvidenceClasses).Count
    Findings = $findings.ToArray()
})

if (-not $Quiet) {
    $result
}

if (-not $result.IsValid) {
    $messages = $findings | ForEach-Object { "- $($_.Rule): $($_.Message)" }
    throw "RoboGuide evidence config validation failed for $($result.Path):`n$($messages -join "`n")"
}
