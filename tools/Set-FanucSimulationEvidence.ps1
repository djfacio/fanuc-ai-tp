param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,31}$')]
    [string]$ProgramName,

    [ValidateSet("not-run", "passed", "failed", "not-required")]
    [string]$Status = "not-run",

    [string]$WorkcellPath,
    [bool]$MotionInvolved = $false,
    [string]$Notes
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$program = $ProgramName.ToUpperInvariant()
$jobDir = Join-Path (Join-Path $projectRoot "generated\jobs") $program
$evidencePath = Join-Path $jobDir "simulation.json"

if (-not (Test-Path -LiteralPath $jobDir)) {
    New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
}

$previous = if (Test-Path -LiteralPath $evidencePath) {
    Get-Content -LiteralPath $evidencePath -Raw | ConvertFrom-Json
} else {
    $null
}

$record = [ordered]@{
    updatedAt = (Get-Date).ToString("o")
    programName = $program
    status = $Status
    workcellPath = if ($WorkcellPath) { $WorkcellPath } elseif ($null -ne $previous) { $previous.workcellPath } else { $null }
    motionInvolved = $MotionInvolved
    notes = if ($Notes) { $Notes } elseif ($null -ne $previous) { $previous.notes } else { $null }
}

$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding ASCII

[pscustomobject]@{
    ProgramName = $program
    Status = $Status
    EvidencePath = (Get-Item -LiteralPath $evidencePath).FullName
}
