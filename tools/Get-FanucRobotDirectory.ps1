param(
    [string]$Pattern = "AI_*.TP",
    [string]$ConfigPath = "..\config\robot.psd1"
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path

if ([System.IO.Path]::IsPathRooted($ConfigPath)) {
    $resolvedConfig = Resolve-Path -LiteralPath $ConfigPath
} else {
    $resolvedConfig = Resolve-Path -LiteralPath (Join-Path $scriptRoot $ConfigPath)
}

$config = Import-PowerShellDataFile -LiteralPath $resolvedConfig

function Invoke-FtpScript {
    param(
        [string[]]$Commands,
        [string]$RobotIp
    )

    $ftpScript = Join-Path $env:TEMP ("fanuc-dir-{0}.ftp" -f ([Guid]::NewGuid().ToString("N")))
    try {
        Set-Content -LiteralPath $ftpScript -Value $Commands -Encoding ASCII
        $previousErrorActionPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $output = & ftp.exe -n -s:$ftpScript $RobotIp 2>&1
        }
        finally {
            $ErrorActionPreference = $previousErrorActionPreference
        }
        [pscustomobject]@{
            ExitCode = $LASTEXITCODE
            Output = @($output)
        }
    }
    finally {
        if (Test-Path -LiteralPath $ftpScript) {
            Remove-Item -LiteralPath $ftpScript -Force
        }
    }
}

function ConvertTo-WildcardRegex {
    param([string]$Wildcard)

    $escaped = [regex]::Escape($Wildcard)
    return "^" + ($escaped -replace "\\\*", ".*" -replace "\\\?", ".") + "$"
}

$directory = Invoke-FtpScript -RobotIp $config.RobotIp -Commands @(
    "user $($config.UserName) $($config.Password)",
    "binary",
    "dir",
    "quit"
)

$ftpText = $directory.Output -join "`n"
if (
    $directory.ExitCode -ne 0 -or
    $ftpText -match '(?i)connect\s*:' -or
    $ftpText -match '(?i)not connected' -or
    $ftpText -match '(?i)login failed' -or
    $ftpText -match '(?i)unknown host' -or
    ($ftpText -match '(?im)^5\d\d\s' -and $ftpText -notmatch '(?im)^226\s')
) {
    throw "FTP directory listing failed:`n$ftpText"
}

$patternRegex = ConvertTo-WildcardRegex $Pattern
$records = foreach ($line in $directory.Output) {
    $text = [string]$line
    if ([string]::IsNullOrWhiteSpace($text)) {
        continue
    }

    $name = $null
    $size = $null

    if ($text -match '^\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\d+\s+\d{4}\s+(.+)$') {
        $size = [int64]$matches[1]
        $name = $matches[2].Trim()
    } elseif ($text -match '^\S+\s+\d+\s+\S+\s+\S+\s+(\d+)\s+\S+\s+\d+\s+\d{1,2}:\d{2}\s+(.+)$') {
        $size = [int64]$matches[1]
        $name = $matches[2].Trim()
    }

    if (-not $name) {
        continue
    }

    if ($name -notmatch $patternRegex) {
        continue
    }

    $programName = [System.IO.Path]::GetFileNameWithoutExtension($name).ToUpperInvariant()
    [pscustomobject]@{
        Name = $name
        ProgramName = $programName
        Extension = [System.IO.Path]::GetExtension($name).ToUpperInvariant()
        Size = $size
        RawLine = $text
    }
}

$records | Sort-Object ProgramName, Name
