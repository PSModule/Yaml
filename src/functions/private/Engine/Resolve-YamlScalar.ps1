function Resolve-YamlScalar {
    <#
        .SYNOPSIS
        Constructs and caches a safe PowerShell scalar using YAML 1.2 rules.

        .DESCRIPTION
        Resolves scalar node content according to an explicit tag or the YAML 1.2
        core implicit rules and caches the result on the node. It validates numeric
        limits, timestamps, and Base64 so projection uses safe .NET values.

        .EXAMPLE
        Resolve-YamlScalar -Node $node

        Returns a value box containing the resolved scalar and caches it on the node.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # Provides the scalar representation node whose tag and text must be constructed.
        [Parameter(Mandatory)]
        [pscustomobject] $Node
    )

    if ($Node.ResolutionState -eq 1) {
        return New-YamlValueBox -Value $Node.ResolvedValue
    }

    $tagPrefix = 'tag:yaml.org,2002:'
    $tag = [string] $Node.Tag
    $value = [string] $Node.Value
    $isImplicit = [string]::IsNullOrEmpty($tag) -and $Node.IsPlainImplicit
    $standardTag = if ($isImplicit) { '' } elseif (
        $tag.StartsWith($tagPrefix, [System.StringComparison]::Ordinal)
    ) {
        $tag.Substring($tagPrefix.Length)
    } else {
        ''
    }
    $resolved = $value

    if ($Node.HasUnknownTag -or (-not $isImplicit -and [string]::IsNullOrEmpty($standardTag))) {
        $resolved = $value
    } elseif ($standardTag -ceq 'str') {
        $resolved = $value
    } elseif (($standardTag -ceq 'null' -or $isImplicit) -and
        $value -cmatch '^(?:|~|null|Null|NULL)$') {
        $resolved = $null
    } elseif (($standardTag -ceq 'bool' -or $isImplicit) -and
        $value -cmatch '^(?:true|True|TRUE|false|False|FALSE)$') {
        $resolved = $value[0] -ceq 't' -or $value[0] -ceq 'T'
    } elseif (($standardTag -ceq 'int' -or $isImplicit) -and
        $value -cmatch '^(?:[-+]?[0-9]+|[-+]?0o[0-7]+|[-+]?0x[0-9a-fA-F]+)$') {
        $digits = $value.TrimStart('+', '-')
        if ($digits.StartsWith('0o', [System.StringComparison]::Ordinal) -or
            $digits.StartsWith('0x', [System.StringComparison]::Ordinal)) {
            $digits = $digits.Substring(2)
        }
        if ($digits.Length -gt $Node.MaxNumericLength) {
            throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlNumericLimitExceeded' -Message (
                    "A YAML numeric scalar exceeds the configured limit of $($Node.MaxNumericLength) digits."
                ))
        }
        $resolved = ConvertFrom-YamlInteger -Value $value
    } elseif (($standardTag -ceq 'float' -or $isImplicit) -and
        $value -cmatch '^[-+]?\.(?:inf|Inf|INF)$') {
        $resolved = if ($value.StartsWith('-', [System.StringComparison]::Ordinal)) {
            [double]::NegativeInfinity
        } else {
            [double]::PositiveInfinity
        }
    } elseif (($standardTag -ceq 'float' -or $isImplicit) -and
        $value -cmatch '^\.(?:nan|NaN|NAN)$') {
        $resolved = [double]::NaN
    } elseif (($standardTag -ceq 'float' -or $isImplicit) -and
        $value -cmatch '^[-+]?(?:(?:\.[0-9]+)|(?:[0-9]+(?:\.[0-9]*)?))(?:[eE][-+]?[0-9]+)?$') {
        $numericCharacters = ($value -replace '[^0-9]', '').Length
        if ($numericCharacters -gt $Node.MaxNumericLength) {
            throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlNumericLimitExceeded' -Message (
                    "A YAML numeric scalar exceeds the configured limit of $($Node.MaxNumericLength) digits."
                ))
        }
        if ($value.IndexOfAny(@('e', 'E')) -lt 0) {
            $decimalValue = [decimal] 0
            if ([decimal]::TryParse(
                    $value,
                    [System.Globalization.NumberStyles]::Number,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref] $decimalValue
                )) {
                $resolved = $decimalValue
            } else {
                $number = [double] 0
                if (-not [double]::TryParse(
                        $value,
                        [System.Globalization.NumberStyles]::Float,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [ref] $number
                    ) -or [double]::IsInfinity($number)) {
                    throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlFloatOverflow' -Message (
                            "The finite YAML floating-point value '$value' is outside the supported range."
                        ))
                }
                $resolved = $number
            }
        } else {
            $number = [double] 0
            if (-not [double]::TryParse(
                    $value,
                    [System.Globalization.NumberStyles]::Float,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref] $number
                ) -or [double]::IsInfinity($number)) {
                throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlFloatOverflow' -Message (
                        "The finite YAML floating-point value '$value' is outside the supported range."
                    ))
            }
            $resolved = $number
        }
    } elseif ($standardTag -ceq 'binary') {
        try {
            $resolved = [System.Convert]::FromBase64String(($value -replace '[ \t\n]', ''))
        } catch [System.FormatException] {
            throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlInvalidBinary' -Message (
                    "The value for tag 'tag:yaml.org,2002:binary' is not valid Base64."
                ))
        }
    } elseif ($standardTag -ceq 'timestamp') {
        $timestampPattern = '^\d{4}-\d{2}-\d{2}(?:[Tt ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[ \t]*(?:[Zz]|[-+]\d{1,2}(?::?\d{2})?))?)?$'
        if ($value -cnotmatch $timestampPattern) {
            throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlInvalidTimestamp' -Message (
                    "The value '$value' is not a supported YAML timestamp."
                ))
        }

        $date = [datetime]::MinValue
        $utcStyles = (
            [System.Globalization.DateTimeStyles]::AssumeUniversal -bor
            [System.Globalization.DateTimeStyles]::AdjustToUniversal
        )
        if ([datetime]::TryParseExact(
                $value,
                'yyyy-MM-dd',
                [System.Globalization.CultureInfo]::InvariantCulture,
                $utcStyles,
                [ref] $date
            )) {
            $resolved = [datetime]::SpecifyKind($date, [System.DateTimeKind]::Utc)
        } else {
            $normalized = $value -replace '[ \t]+([+-]\d{1,2}(?::?\d{2})?)$', '$1'
            if ($normalized -match '([+-])(\d{1,2})(?::?(\d{2}))?$') {
                $minutes = if ($Matches[3]) { $Matches[3] } else { '00' }
                $suffix = '{0}{1}:{2}' -f $Matches[1], $Matches[2].PadLeft(2, '0'), $minutes
                $normalized = $normalized.Substring(0, $normalized.Length - $Matches[0].Length) + $suffix
            }
            if ($normalized -cmatch '(?:[Zz]|[-+]\d{2}:\d{2})$') {
                $offset = [datetimeoffset]::MinValue
                if (-not [datetimeoffset]::TryParse(
                        $normalized,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
                        [ref] $offset
                    )) {
                    throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlInvalidTimestamp' -Message (
                            "The value '$value' is not a supported YAML timestamp."
                        ))
                }
                $resolved = $offset
            } else {
                $dateTime = [datetime]::MinValue
                if (-not [datetime]::TryParse(
                        $normalized,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        $utcStyles,
                        [ref] $dateTime
                    )) {
                    throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlInvalidTimestamp' -Message (
                            "The value '$value' is not a supported YAML timestamp."
                        ))
                }
                $resolved = [datetime]::SpecifyKind($dateTime, [System.DateTimeKind]::Utc)
            }
        }
    } elseif (-not $isImplicit -and $standardTag -cin @('null', 'bool', 'int', 'float')) {
        throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlInvalidTaggedScalar' -Message (
                "The value '$value' is invalid for YAML tag '$tag'."
            ))
    } else {
        $resolved = $value
    }

    $Node.ResolvedValue = $resolved
    $Node.ResolutionState = 1
    return New-YamlValueBox -Value $resolved
}
