param(
    [Parameter(Mandatory = $true)]
    [string]$JsonPath,

    [Parameter(Mandatory = $true)]
    [string]$SchemaPath,

    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

$resolvedJson = Resolve-Path -LiteralPath $JsonPath
$resolvedSchema = Resolve-Path -LiteralPath $SchemaPath
$json = Get-Content -LiteralPath $resolvedJson -Raw | ConvertFrom-Json
$schema = Get-Content -LiteralPath $resolvedSchema -Raw | ConvertFrom-Json

$result = [ordered]@{
    Path = (Get-Item -LiteralPath $resolvedJson).FullName
    SchemaPath = (Get-Item -LiteralPath $resolvedSchema).FullName
    IsValid = $true
    Findings = @()
}

function Add-Finding {
    param(
        [string]$Path,
        [string]$Rule,
        [string]$Message
    )

    $result.IsValid = $false
    $result.Findings += [pscustomobject]@{
        Path = $Path
        Rule = $Rule
        Message = $Message
    }
}

function Test-JsonType {
    param(
        [object]$Value,
        [string]$Type
    )

    switch ($Type) {
        "object" { return ($null -ne $Value -and $Value -is [pscustomobject]) }
        "array" { return ($null -ne $Value -and ($Value -is [array] -or $Value -is [System.Collections.IEnumerable]) -and -not ($Value -is [string]) -and -not ($Value -is [pscustomobject])) }
        "string" { return ($Value -is [string]) }
        "integer" { return ($Value -is [int] -or $Value -is [long]) }
        "number" { return ($Value -is [int] -or $Value -is [long] -or $Value -is [double] -or $Value -is [decimal]) }
        "boolean" { return ($Value -is [bool]) }
        default { return $true }
    }
}

function Get-PropertyNames {
    param([object]$Object)

    if ($null -eq $Object -or -not ($Object -is [pscustomobject])) {
        return @()
    }

    return @($Object.PSObject.Properties | ForEach-Object { $_.Name })
}

function Test-SchemaNode {
    param(
        [object]$Value,
        [object]$SchemaNode,
        [string]$Path
    )

    if ($null -eq $SchemaNode) {
        return
    }

    if ($SchemaNode.PSObject.Properties.Name -contains "type") {
        if (-not (Test-JsonType -Value $Value -Type $SchemaNode.type)) {
            Add-Finding -Path $Path -Rule "Type" -Message "Expected type '$($SchemaNode.type)'."
            return
        }
    }

    if ($SchemaNode.PSObject.Properties.Name -contains "enum") {
        $allowed = @($SchemaNode.enum)
        if ($allowed -notcontains $Value) {
            Add-Finding -Path $Path -Rule "Enum" -Message "Value must be one of: $($allowed -join ', ')."
        }
    }

    if ($SchemaNode.PSObject.Properties.Name -contains "pattern" -and $Value -is [string]) {
        if ($Value -notmatch $SchemaNode.pattern) {
            Add-Finding -Path $Path -Rule "Pattern" -Message "Value does not match pattern $($SchemaNode.pattern)."
        }
    }

    if ($SchemaNode.PSObject.Properties.Name -contains "minLength" -and $Value -is [string]) {
        if ($Value.Length -lt [int]$SchemaNode.minLength) {
            Add-Finding -Path $Path -Rule "MinLength" -Message "Value length must be at least $($SchemaNode.minLength)."
        }
    }

    if ($SchemaNode.PSObject.Properties.Name -contains "minimum" -and $null -ne $Value) {
        if ([double]$Value -lt [double]$SchemaNode.minimum) {
            Add-Finding -Path $Path -Rule "Minimum" -Message "Value must be at least $($SchemaNode.minimum)."
        }
    }

    if ($SchemaNode.PSObject.Properties.Name -contains "minItems") {
        if (@($Value).Count -lt [int]$SchemaNode.minItems) {
            Add-Finding -Path $Path -Rule "MinItems" -Message "Array must contain at least $($SchemaNode.minItems) item(s)."
        }
    }

    if ($SchemaNode.PSObject.Properties.Name -contains "required") {
        $names = Get-PropertyNames -Object $Value
        foreach ($required in @($SchemaNode.required)) {
            if ($names -notcontains $required) {
                Add-Finding -Path $Path -Rule "Required" -Message "Missing required property '$required'."
            }
        }
    }

    if ($SchemaNode.PSObject.Properties.Name -contains "additionalProperties" -and $SchemaNode.additionalProperties -eq $false -and $SchemaNode.PSObject.Properties.Name -contains "properties") {
        $allowed = Get-PropertyNames -Object $SchemaNode.properties
        foreach ($name in (Get-PropertyNames -Object $Value)) {
            if ($allowed -notcontains $name) {
                Add-Finding -Path "$Path.$name" -Rule "AdditionalProperties" -Message "Additional property '$name' is not allowed."
            }
        }
    }

    if ($SchemaNode.PSObject.Properties.Name -contains "properties" -and $Value -is [pscustomobject]) {
        foreach ($property in $SchemaNode.properties.PSObject.Properties) {
            if ($Value.PSObject.Properties.Name -contains $property.Name) {
                Test-SchemaNode -Value $Value.($property.Name) -SchemaNode $property.Value -Path "$Path.$($property.Name)"
            }
        }
    }

    if ($SchemaNode.PSObject.Properties.Name -contains "items" -and $null -ne $Value) {
        $index = 0
        foreach ($item in @($Value)) {
            Test-SchemaNode -Value $item -SchemaNode $SchemaNode.items -Path "$Path[$index]"
            $index++
        }
    }
}

Test-SchemaNode -Value $json -SchemaNode $schema -Path "$"

$output = [pscustomobject]$result
if (-not $Quiet) {
    $output
}

if (-not $result.IsValid) {
    $messages = $result.Findings | ForEach-Object { "- $($_.Path) $($_.Rule): $($_.Message)" }
    throw "JSON schema validation failed for $($result.Path):`n$($messages -join "`n")"
}
