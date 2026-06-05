param(
    [string]$HostAddress = "",
    [string[]]$Families = @("R", "PR", "SR", "UALM", "RI", "RO", "DI", "DO", "GI", "GO", "AI", "AO", "F"),
    [int]$StartIndex = 1,
    [int]$EndIndex = 0,
    [string]$OutputPath = "",
    [switch]$IncludeValues
)

$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptRoot

if (-not $HostAddress) {
    $robotConfigPath = Join-Path $repoRoot "config\robot.psd1"
    if (Test-Path -LiteralPath $robotConfigPath) {
        $robotConfig = Import-PowerShellDataFile -LiteralPath $robotConfigPath
        $HostAddress = [string]$robotConfig.RobotIp
    }
}
if (-not $HostAddress) {
    throw "HostAddress was not supplied and config\robot.psd1 did not provide RobotIp."
}

$familyPages = @{
    R    = @{ FunctionCode = 28; Title = "Numeric Registers"; HasValue = $true; ValueName = "Value" }
    PR   = @{ FunctionCode = 29; Title = "Position Registers"; HasValue = $false }
    SR   = @{ FunctionCode = 30; Title = "String Registers"; HasValue = $true; ValueName = "Value" }
    UALM = @{ FunctionCode = 31; Title = "User Alarms"; HasValue = $true; ValueName = "Severity" }
    RI   = @{ FunctionCode = 32; Title = "Robot I/O"; HasValue = $false }
    RO   = @{ FunctionCode = 32; Title = "Robot I/O"; HasValue = $false }
    DI   = @{ FunctionCode = 33; Title = "Digital I/O"; HasValue = $false }
    DO   = @{ FunctionCode = 33; Title = "Digital I/O"; HasValue = $false }
    GI   = @{ FunctionCode = 34; Title = "Group I/O"; HasValue = $false }
    GO   = @{ FunctionCode = 34; Title = "Group I/O"; HasValue = $false }
    AI   = @{ FunctionCode = 35; Title = "Analog I/O"; HasValue = $false }
    AO   = @{ FunctionCode = 35; Title = "Analog I/O"; HasValue = $false }
    F    = @{ FunctionCode = 76; Title = "Flag"; HasValue = $false }
}

$labelPrefix = @{
    R    = "R"
    PR   = "PR"
    SR   = "SR"
    UALM = "User Alarm"
    RI   = "RI"
    RO   = "RO"
    DI   = "DI"
    DO   = "DO"
    GI   = "GI"
    GO   = "GO"
    AI   = "AI"
    AO   = "AO"
    F    = "F"
}

$severityNames = @{
    0  = "WARN"
    6  = "STOP.L"
    11 = "ABORT.L"
    38 = "STOP.G"
    43 = "ABORT.G"
}

function ConvertFrom-HtmlValue {
    param([string]$Value)
    if ($null -eq $Value) {
        return ""
    }
    return [System.Net.WebUtility]::HtmlDecode($Value)
}

function Get-RobotServerPage {
    param(
        [string]$RobotHost,
        [int]$FunctionCode,
        [hashtable]$Cache
    )

    if ($Cache.ContainsKey($FunctionCode)) {
        return $Cache[$FunctionCode]
    }

    $uri = "http://$RobotHost/KAREL/ComGet?sFc=$FunctionCode"
    $response = Invoke-WebRequest -Uri $uri -Method Get -TimeoutSec 20 -UseBasicParsing
    $Cache[$FunctionCode] = [pscustomobject]@{
        Uri = $uri
        StatusCode = [int]$response.StatusCode
        ContentType = [string]$response.Headers["Content-Type"]
        Html = [string]$response.Content
    }
    return $Cache[$FunctionCode]
}

function Get-InputsAfterLabel {
    param(
        [string]$Html,
        [string]$Label
    )

    $escapedLabel = [regex]::Escape($Label)
    $labelMatch = [regex]::Match($Html, $escapedLabel, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $labelMatch.Success) {
        return @()
    }

    $nextLabel = [regex]::Match(
        $Html.Substring($labelMatch.Index + $labelMatch.Length),
        '(<td[^>]*>\s*<p[^>]*>\s*(?:R|PR|SR|RI|RO|DI|DO|GI|GO|AI|AO|F|User Alarm)\[\d+\])',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if ($nextLabel.Success) {
        $segment = $Html.Substring($labelMatch.Index, $labelMatch.Length + $nextLabel.Index)
    } else {
        $segment = $Html.Substring($labelMatch.Index)
    }

    $matches = [regex]::Matches(
        $segment,
        '<input\b[^>]*\bvalue="([^"]*)"',
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )
    return @($matches | ForEach-Object { ConvertFrom-HtmlValue $_.Groups[1].Value })
}

$normalizedFamilies = @(
    foreach ($family in $Families) {
        $upper = $family.ToUpperInvariant()
        if (-not $familyPages.ContainsKey($upper)) {
            throw "Unsupported family '$family'. Supported families: $(@($familyPages.Keys | Sort-Object) -join ', ')"
        }
        $upper
    }
) | Select-Object -Unique

$pageCache = @{}
$items = New-Object System.Collections.Generic.List[object]

foreach ($family in $normalizedFamilies) {
    $pageInfo = $familyPages[$family]
    $page = Get-RobotServerPage -RobotHost $HostAddress -FunctionCode ([int]$pageInfo.FunctionCode) -Cache $pageCache
    $prefix = $labelPrefix[$family]
    $labelRegex = [regex]::Escape($prefix) + '\[(\d+)\]'
    $indexes = [regex]::Matches($page.Html, $labelRegex, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase) |
        ForEach-Object { [int]$_.Groups[1].Value } |
        Sort-Object -Unique

    foreach ($index in $indexes) {
        if ($index -lt $StartIndex) {
            continue
        }
        if ($EndIndex -gt 0 -and $index -gt $EndIndex) {
            continue
        }

        $label = "$prefix[$index]"
        $inputs = @(Get-InputsAfterLabel -Html $page.Html -Label $label)
        $comment = ""
        $value = $null
        if ($inputs.Count -gt 0) {
            $comment = [string]$inputs[0]
        }
        if ([bool]$pageInfo.HasValue -and $inputs.Count -gt 1) {
            $value = [string]$inputs[1]
        }

        $row = [ordered]@{
            Family = $family
            Index = $index
            Name = $label
            Comment = $comment
            Source = "robot-server"
            Uri = $page.Uri
        }
        if ($IncludeValues -and [bool]$pageInfo.HasValue) {
            $row[$pageInfo.ValueName] = $value
            if ($family -eq "UALM") {
                $severityInt = 0
                if ([int]::TryParse($value, [ref]$severityInt) -and $severityNames.ContainsKey($severityInt)) {
                    $row["SeverityName"] = $severityNames[$severityInt]
                }
            }
        }

        $items.Add([pscustomobject]$row)
    }
}

$result = [pscustomobject]@{
    HostAddress = $HostAddress
    CapturedAt = (Get-Date).ToString("o")
    Mode = "read-only"
    Endpoint = "robot-server"
    Families = $normalizedFamilies
    StartIndex = $StartIndex
    EndIndex = $EndIndex
    Count = $items.Count
    Items = $items.ToArray()
}

if ($OutputPath) {
    $resolvedOutput = if ([System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath
    } else {
        Join-Path $repoRoot $OutputPath
    }
    $outputDir = Split-Path -Parent $resolvedOutput
    if ($outputDir -and -not (Test-Path -LiteralPath $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resolvedOutput -Encoding UTF8
}

$result
