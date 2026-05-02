function ConvertTo-YamlNode {
    <#
        .SYNOPSIS
        Recursively writes a value as a YAML block-style node into the supplied StringBuilder.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [System.Text.StringBuilder] $Builder,

        [Parameter(Mandatory)]
        [int] $Level,

        [Parameter(Mandatory)]
        [int] $CurrentDepth,

        [Parameter(Mandatory)]
        [pscustomobject] $Options
    )

    if ($CurrentDepth -gt $Options.Depth) {
        $repr = if ($null -eq $Value) { 'null' } else { Format-YamlScalar -Value $Value.ToString() -Options $Options }
        $null = $Builder.Append($repr).AppendLine()
        return
    }

    if ($null -eq $Value) {
        $null = $Builder.Append('null').AppendLine()
        return
    }

    # Unwrap PSObject for type tests.
    $raw = if ($Value -is [psobject] -and $null -ne $Value.PSObject -and $null -ne $Value.PSObject.BaseObject) {
        $Value.PSObject.BaseObject
    } else {
        $Value
    }

    if (Test-YamlMappingType -Value $raw) {
        ConvertTo-YamlMapping -Value $Value -Builder $Builder -Level $Level -CurrentDepth $CurrentDepth -Options $Options
        return
    }

    if (Test-YamlSequenceType -Value $raw) {
        ConvertTo-YamlSequence -Value $raw -Builder $Builder -Level $Level -CurrentDepth $CurrentDepth -Options $Options
        return
    }

    # Scalar.
    $scalar = Format-YamlScalar -Value $raw -Options $Options
    $null = $Builder.Append($scalar).AppendLine()
}

function Test-YamlMappingType {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter()] [AllowNull()] [object] $Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $true }
    if ($Value -is [string]) { return $false }
    if ($Value -is [System.ValueType]) { return $false }
    if ($Value -is [System.Collections.IEnumerable]) { return $false }
    if ($Value -is [psobject] -or $Value -is [System.Management.Automation.PSCustomObject]) { return $true }
    return $false
}

function Test-YamlSequenceType {
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter()] [AllowNull()] [object] $Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $false }
    if ($Value -is [System.Collections.IEnumerable]) { return $true }
    return $false
}

function ConvertTo-YamlMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Value,
        [Parameter(Mandatory)] [System.Text.StringBuilder] $Builder,
        [Parameter(Mandatory)] [int] $Level,
        [Parameter(Mandatory)] [int] $CurrentDepth,
        [Parameter(Mandatory)] [pscustomobject] $Options
    )

    $pairs = Get-YamlMappingPairs -Value $Value
    if ($pairs.Count -eq 0) {
        $null = $Builder.Append('{}').AppendLine()
        return
    }

    $indent = ' ' * ($Level * $Options.Indent)
    foreach ($pair in $pairs) {
        $keyText = Format-YamlKey -Key $pair.Key -Options $Options
        $val = $pair.Value
        $null = $Builder.Append($indent).Append($keyText).Append(':')

        if ($null -eq $val) {
            $null = $Builder.Append(' null').AppendLine()
            continue
        }

        $rawVal = if ($val -is [psobject] -and $null -ne $val.PSObject -and $null -ne $val.PSObject.BaseObject) {
            $val.PSObject.BaseObject
        } else {
            $val
        }

        if (Test-YamlMappingType -Value $rawVal) {
            $childPairs = Get-YamlMappingPairs -Value $val
            if ($childPairs.Count -eq 0) {
                $null = $Builder.Append(' {}').AppendLine()
            } else {
                $null = $Builder.AppendLine()
                ConvertTo-YamlNode -Value $val -Builder $Builder -Level ($Level + 1) -CurrentDepth ($CurrentDepth + 1) -Options $Options
            }
            continue
        }

        if (Test-YamlSequenceType -Value $rawVal) {
            $arr = @($rawVal)
            if ($arr.Count -eq 0) {
                $null = $Builder.Append(' []').AppendLine()
            } else {
                $null = $Builder.AppendLine()
                ConvertTo-YamlSequence -Value $rawVal -Builder $Builder -Level ($Level + 1) -CurrentDepth ($CurrentDepth + 1) -Options $Options
            }
            continue
        }

        $scalar = Format-YamlScalar -Value $rawVal -Options $Options
        $null = $Builder.Append(' ').Append($scalar).AppendLine()
    }
}

function ConvertTo-YamlSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Value,
        [Parameter(Mandatory)] [System.Text.StringBuilder] $Builder,
        [Parameter(Mandatory)] [int] $Level,
        [Parameter(Mandatory)] [int] $CurrentDepth,
        [Parameter(Mandatory)] [pscustomobject] $Options
    )

    $items = @($Value)
    if ($items.Count -eq 0) {
        $null = $Builder.Append('[]').AppendLine()
        return
    }

    $indent = ' ' * ($Level * $Options.Indent)

    foreach ($item in $items) {
        $rawItem = if ($item -is [psobject] -and $null -ne $item.PSObject -and $null -ne $item.PSObject.BaseObject) {
            $item.PSObject.BaseObject
        } else {
            $item
        }

        if ($null -eq $item) {
            $null = $Builder.Append($indent).Append('- null').AppendLine()
            continue
        }

        if (Test-YamlMappingType -Value $rawItem) {
            $pairs = Get-YamlMappingPairs -Value $item
            if ($pairs.Count -eq 0) {
                $null = $Builder.Append($indent).Append('- {}').AppendLine()
                continue
            }
            $first = $true
            $childIndent = ' ' * (($Level + 1) * $Options.Indent)
            foreach ($pair in $pairs) {
                $keyText = Format-YamlKey -Key $pair.Key -Options $Options
                $prefix = if ($first) { "$indent- " } else { $childIndent }
                $first = $false

                $val = $pair.Value
                $rawVal = if ($val -is [psobject] -and $null -ne $val.PSObject -and $null -ne $val.PSObject.BaseObject) {
                    $val.PSObject.BaseObject
                } else {
                    $val
                }

                if ($null -eq $val) {
                    $null = $Builder.Append($prefix).Append($keyText).Append(': null').AppendLine()
                    continue
                }

                if (Test-YamlMappingType -Value $rawVal) {
                    $null = $Builder.Append($prefix).Append($keyText).Append(':').AppendLine()
                    ConvertTo-YamlNode -Value $val -Builder $Builder -Level ($Level + 2) -CurrentDepth ($CurrentDepth + 1) -Options $Options
                    continue
                }

                if (Test-YamlSequenceType -Value $rawVal) {
                    $null = $Builder.Append($prefix).Append($keyText).Append(':').AppendLine()
                    ConvertTo-YamlSequence -Value $rawVal -Builder $Builder -Level ($Level + 2) -CurrentDepth ($CurrentDepth + 1) -Options $Options
                    continue
                }

                $scalar = Format-YamlScalar -Value $rawVal -Options $Options
                $null = $Builder.Append($prefix).Append($keyText).Append(': ').Append($scalar).AppendLine()
            }
            continue
        }

        if (Test-YamlSequenceType -Value $rawItem) {
            $null = $Builder.Append($indent).Append('-').AppendLine()
            ConvertTo-YamlSequence -Value $rawItem -Builder $Builder -Level ($Level + 1) -CurrentDepth ($CurrentDepth + 1) -Options $Options
            continue
        }

        $scalar = Format-YamlScalar -Value $rawItem -Options $Options
        $null = $Builder.Append($indent).Append('- ').Append($scalar).AppendLine()
    }
}

function Get-YamlMappingPairs {
    <#
        .SYNOPSIS
        Returns a list of [pscustomobject]@{ Key; Value } for a dictionary or PSObject.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[pscustomobject]])]
    param(
        [Parameter(Mandatory)]
        [object] $Value
    )

    $pairs = [System.Collections.Generic.List[pscustomobject]]::new()
    $raw = if ($Value -is [psobject] -and $null -ne $Value.PSObject -and $null -ne $Value.PSObject.BaseObject) {
        $Value.PSObject.BaseObject
    } else {
        $Value
    }

    if ($raw -is [System.Collections.IDictionary]) {
        foreach ($key in $raw.Keys) {
            $pairs.Add([pscustomobject]@{ Key = $key; Value = $raw[$key] })
        }
        return , $pairs
    }

    if ($Value -is [psobject]) {
        foreach ($prop in $Value.PSObject.Properties) {
            $pairs.Add([pscustomobject]@{ Key = $prop.Name; Value = $prop.Value })
        }
    }

    return , $pairs
}

function Format-YamlScalar {
    <#
        .SYNOPSIS
        Renders a scalar value as a YAML token.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()] [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [pscustomobject] $Options
    )

    if ($null -eq $Value) { return 'null' }

    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }

    if ($Value -is [System.Enum]) {
        if ($Options.EnumsAsStrings) {
            return Format-YamlString -Text ($Value.ToString())
        }
        return ([int64] $Value).ToString([cultureinfo]::InvariantCulture)
    }

    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int] -or $Value -is [uint32] -or
        $Value -is [long] -or $Value -is [uint64]) {
        return ([System.IConvertible] $Value).ToString([cultureinfo]::InvariantCulture)
    }

    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        return ([System.IConvertible] $Value).ToString([cultureinfo]::InvariantCulture)
    }

    if ($Value -is [datetime]) {
        return $Value.ToString('o', [cultureinfo]::InvariantCulture)
    }

    return Format-YamlString -Text ([string] $Value)
}

function Format-YamlString {
    <#
        .SYNOPSIS
        Renders a string as a YAML scalar, quoting and escaping as needed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    if ($Text.Length -eq 0) { return "''" }

    # Always double-quote strings that contain control characters or quotes that need escaping.
    $needsDoubleQuote = $false
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int] $ch
        if ($code -lt 0x20 -or $code -eq 0x7F) {
            $needsDoubleQuote = $true
            break
        }
    }

    if ($needsDoubleQuote) {
        return Format-YamlDoubleQuoted -Text $Text
    }

    if (Test-YamlPlainSafe -Text $Text) {
        return $Text
    }

    # Prefer single quotes when the text doesn't contain a single quote; otherwise double-quote.
    if ($Text -notmatch "'") {
        return "'$Text'"
    }

    return Format-YamlDoubleQuoted -Text $Text
}

function Format-YamlDoubleQuoted {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int] $ch
        if ($ch -eq '\') { $null = $sb.Append('\\'); continue }
        if ($ch -eq '"') { $null = $sb.Append('\"'); continue }
        if ($ch -eq "`n") { $null = $sb.Append('\n'); continue }
        if ($ch -eq "`t") { $null = $sb.Append('\t'); continue }
        if ($ch -eq "`r") { $null = $sb.Append('\r'); continue }
        if ($code -lt 0x20 -or $code -eq 0x7F) {
            $null = $sb.AppendFormat('\x{0:x2}', $code)
            continue
        }
        $null = $sb.Append($ch)
    }
    $null = $sb.Append('"')
    return $sb.ToString()
}

function Format-YamlKey {
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Key,
        [Parameter(Mandatory)] [pscustomobject] $Options
    )

    $text = [string] $Key
    if ([string]::IsNullOrEmpty($text)) { return "''" }
    if (Test-YamlPlainSafe -Text $text -ForKey) {
        return $text
    }
    if ($text -notmatch "'") { return "'$text'" }
    return Format-YamlDoubleQuoted -Text $text
}

function Test-YamlPlainSafe {
    <#
        .SYNOPSIS
        Returns $true when a string can be emitted as a plain (unquoted) YAML scalar.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter()]
        [switch] $ForKey
    )

    if ($Text.Length -eq 0) { return $false }
    if ($Text -ne $Text.Trim()) { return $false }

    # Strings that look like reserved literals must be quoted to preserve the string type.
    $reserved = @(
        'true', 'True', 'TRUE',
        'false', 'False', 'FALSE',
        'yes', 'Yes', 'YES',
        'no', 'No', 'NO',
        'on', 'On', 'ON',
        'off', 'Off', 'OFF',
        'null', 'Null', 'NULL',
        '~'
    )
    if ($Text -in $reserved) { return $false }

    # Strings that parse as a number must be quoted.
    $tmpInt = 0L
    if ([long]::TryParse($Text, [System.Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref] $tmpInt)) {
        return $false
    }
    $tmpDbl = 0.0
    if ([double]::TryParse($Text, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref] $tmpDbl)) {
        return $false
    }

    # Disallowed leading characters per YAML plain scalar rules.
    $first = $Text[0]
    $disallowedFirst = @('-', '?', ':', ',', '[', ']', '{', '}', '#', '&', '*', '!', '|', '>', "'", '"', '%', '@', '`')
    if ($disallowedFirst -contains [string] $first) { return $false }

    foreach ($ch in $Text.ToCharArray()) {
        $code = [int] $ch
        if ($code -lt 0x20 -or $code -eq 0x7F) { return $false }
    }

    # Disallowed characters anywhere (would confuse parsing).
    if ($Text -match '[:#]') {
        # ': ' or ' #' would be ambiguous; conservatively quote whenever ':' or '#' appear.
        return $false
    }

    if ($ForKey) {
        if ($Text -match '[\[\]\{\},&*!|>''"%@`]') { return $false }
    }

    return $true
}
