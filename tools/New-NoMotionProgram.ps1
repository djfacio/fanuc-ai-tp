param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z][A-Za-z0-9_]{0,31}$')]
    [string]$Name,

[string]$Message = "A FTP upload OK",
    [int]$Register = 99,
    [int]$Value = 123,
    [string]$ConfigPath = "..\config\robot.psd1"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptRoot
if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}
$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig

$programName = $Name.ToUpperInvariant()
if (-not $programName.StartsWith($config.ProgramPrefix.ToUpperInvariant())) {
    throw "Program name must start with $($config.ProgramPrefix). Example: A_HELLO"
}

if ($Message.Length -gt 24) {
    throw "FANUC MESSAGE text should stay short. Use 24 characters or fewer."
}

$safeMessage = $Message.ToUpperInvariant() -replace '[^\w \-]', ''
if ($safeMessage.Length -eq 0) {
    throw "Message became empty after safety filtering."
}

$sourcesDir = Join-Path $projectRoot "generated\sources"
$outPath = Join-Path $sourcesDir ($programName + ".LS")
$now = Get-Date
$date = $now.ToString("yy-MM-dd")
$time = $now.ToString("HH:mm:ss")

$content = @"
/PROG $programName
/ATTR
OWNER = MNEDITOR;
COMMENT = "AI NO MOTION";
PROG_SIZE = 0;
CREATE = DATE $date  TIME $time;
MODIFIED = DATE $date  TIME $time;
FILE_NAME = ;
VERSION = 0;
LINE_COUNT = 2;
MEMORY_SIZE = 0;
PROTECT = READ_WRITE;
TCD: STACK_SIZE = 0,
     TASK_PRIORITY = 50,
     TIME_SLICE = 0,
     BUSY_LAMP_OFF = 0,
     ABORT_REQUEST = 0,
     PAUSE_REQUEST = 0;
DEFAULT_GROUP = *,*,*,*,*,*,*,*;
CONTROL_CODE = 00000000 00000000;
/MN
   1:  MESSAGE[$safeMessage] ;
   2:  R[$Register]=$Value ;
/POS
/END
"@

Set-Content -LiteralPath $outPath -Value $content -Encoding ASCII
Get-Item -LiteralPath $outPath
