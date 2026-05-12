param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("probe", "read-r", "asg-read", "asg-write-r", "write-r", "command-g")]
    [string]$Operation,

    [string]$HostAddress = "192.168.5.10:60008",
    [ValidateSet("fanuc-snpx", "srtp")]
    [string]$PortKind = "fanuc-snpx",

    [int]$Start,
    [int]$Count,
    [int]$Value,
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
