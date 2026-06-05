param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("probe", "read-r", "asg-read", "asg-write-r", "asg-read-ualm-severity", "asg-write-ualm-severity", "asg-write-r-text", "write-r", "command-g")]
    [string]$Operation,

    [string]$HostAddress = "192.168.0.10:60008",
    [ValidateSet("fanuc-snpx", "srtp")]
    [string]$PortKind = "fanuc-snpx",

    [int]$Start,
    [int]$Count,
    [int]$Value,
    [ValidateSet("WARN", "STOP.L", "STOP.G", "ABORT.L", "ABORT.G", "0", "6", "38", "11", "43")]
    [string]$Severity,
    [string]$Text,
    [string]$SetupFile,

    [switch]$AcceptLiveWrite
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
$manifestPath = Join-Path $projectRoot "vendor\snpx-codec\Cargo.toml"

if (-not (Test-Path -LiteralPath $manifestPath)) {
    throw "Local SNPX codec manifest not found at $manifestPath."
}

$toolArgs = @(
    "run",
    "--quiet",
    "--manifest-path",
    $manifestPath,
    "--bin",
    "fanuc-snpx-tool",
    "--",
    $Operation,
    "--host",
    $HostAddress,
    "--port-kind",
    $PortKind
)

switch ($Operation) {
    "read-r" {
        if ($Start -lt 1 -or $Count -lt 1) {
            throw "read-r requires -Start >= 1 and -Count >= 1."
        }
        $toolArgs += @("--start", [string]$Start, "--count", [string]$Count)
    }
    "write-r" {
        if (-not $AcceptLiveWrite) {
            throw "write-r requires -AcceptLiveWrite. Use New-FanucSnpxWritePlan.ps1 first."
        }
        if ($Start -lt 1) {
            throw "write-r requires -Start >= 1."
        }
        $toolArgs += @("--start", [string]$Start, "--value", [string]$Value, "--i-accept-live-write")
    }
    "asg-read" {
        if (-not $SetupFile) {
            throw "asg-read requires -SetupFile."
        }
        if (-not (Test-Path -LiteralPath $SetupFile)) {
            throw "asg-read setup file not found: $SetupFile"
        }
        if ($Start -lt 1 -or $Count -lt 1) {
            throw "asg-read requires -Start >= 1 and -Count >= 1."
        }
        $toolArgs += @("--setup-file", (Resolve-Path -LiteralPath $SetupFile).Path, "--start", [string]$Start, "--count", [string]$Count)
    }
    "asg-write-r" {
        if (-not $AcceptLiveWrite) {
            throw "asg-write-r requires -AcceptLiveWrite. Use New-FanucSnpxWritePlan.ps1 first."
        }
        if (-not $SetupFile) {
            throw "asg-write-r requires -SetupFile."
        }
        if (-not (Test-Path -LiteralPath $SetupFile)) {
            throw "asg-write-r setup file not found: $SetupFile"
        }
        if ($Start -lt 1) {
            throw "asg-write-r requires -Start >= 1."
        }
        $toolArgs += @("--setup-file", (Resolve-Path -LiteralPath $SetupFile).Path, "--start", [string]$Start, "--value", [string]$Value, "--i-accept-live-write")
    }
    "asg-read-ualm-severity" {
        if (-not $SetupFile) {
            throw "asg-read-ualm-severity requires -SetupFile."
        }
        if (-not (Test-Path -LiteralPath $SetupFile)) {
            throw "asg-read-ualm-severity setup file not found: $SetupFile"
        }
        if ($Start -lt 1) {
            throw "asg-read-ualm-severity requires -Start >= 1."
        }
        $toolArgs += @("--setup-file", (Resolve-Path -LiteralPath $SetupFile).Path, "--start", [string]$Start)
    }
    "asg-write-ualm-severity" {
        if (-not $AcceptLiveWrite) {
            throw "asg-write-ualm-severity requires -AcceptLiveWrite and an approved alarm severity plan."
        }
        if (-not $SetupFile) {
            throw "asg-write-ualm-severity requires -SetupFile."
        }
        if (-not (Test-Path -LiteralPath $SetupFile)) {
            throw "asg-write-ualm-severity setup file not found: $SetupFile"
        }
        if ($Start -lt 1) {
            throw "asg-write-ualm-severity requires -Start >= 1."
        }
        if (-not $Severity) {
            throw "asg-write-ualm-severity requires -Severity."
        }
        $toolArgs += @("--setup-file", (Resolve-Path -LiteralPath $SetupFile).Path, "--start", [string]$Start, "--severity", $Severity, "--i-accept-live-write")
    }
    "asg-write-r-text" {
        if (-not $AcceptLiveWrite) {
            throw "asg-write-r-text requires -AcceptLiveWrite. Use only after a reviewed proof plan."
        }
        if (-not $SetupFile) {
            throw "asg-write-r-text requires -SetupFile."
        }
        if (-not (Test-Path -LiteralPath $SetupFile)) {
            throw "asg-write-r-text setup file not found: $SetupFile"
        }
        if ($Start -lt 1) {
            throw "asg-write-r-text requires -Start >= 1."
        }
        if (-not $Text) {
            throw "asg-write-r-text requires -Text."
        }
        $wordCount = if ($Count -ge 1) { $Count } else { 30 }
        $toolArgs += @("--setup-file", (Resolve-Path -LiteralPath $SetupFile).Path, "--start", [string]$Start, "--text", $Text, "--word-count", [string]$wordCount, "--i-accept-live-write")
    }
    "command-g" {
        if (-not $AcceptLiveWrite) {
            throw "command-g requires -AcceptLiveWrite."
        }
        if (-not $Text) {
            throw "command-g requires -Text."
        }
        $toolArgs += @("--text", $Text, "--i-accept-live-write")
    }
}

& cargo @toolArgs
