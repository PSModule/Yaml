function Resolve-YamlScalar {
    <#
        .SYNOPSIS
        Constructs a safe PowerShell scalar using YAML 1.2 schema rules.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node
    )

    $tagPrefix = 'tag:yaml.org,2002:'
    $tag = [string] $Node.Tag
    $value = [string] $Node.Value
    $isImplicit = [string]::IsNullOrEmpty($tag) -and $Node.IsPlainImplicit

    if (-not $isImplicit -and -not $tag.StartsWith($tagPrefix, [System.StringComparison]::Ordinal)) {
        Write-Output -InputObject $value -NoEnumerate
        return
    }

    $standardTag = if ($isImplicit) { '' } else { $tag.Substring($tagPrefix.Length) }
    $nullPattern = '^(?:|~|null|Null|NULL)$'
    $booleanPattern = '^(?:true|True|TRUE|false|False|FALSE)$'
    $integerPattern = '^(?:[-+]?[0-9]+|0o[0-7]+|0x[0-9a-fA-F]+)$'
    $numberPattern = '^[-+]?(?:(?:\.[0-9]+)|(?:[0-9]+(?:\.[0-9]*)?))(?:[eE][-+]?[0-9]+)?$'
    $infinityPattern = '^[-+]?\.(?:inf|Inf|INF)$'
    $nanPattern = '^\.(?:nan|NaN|NAN)$'

    if ($standardTag -eq 'str') {
        Write-Output -InputObject $value -NoEnumerate
        return
    }

    if (($standardTag -eq 'null' -or $isImplicit) -and $value -cmatch $nullPattern) {
        return
    }

    if (($standardTag -eq 'bool' -or $isImplicit) -and $value -cmatch $booleanPattern) {
        Write-Output -InputObject ($value[0] -ceq 't' -or $value[0] -ceq 'T') -NoEnumerate
        return
    }

    if (($standardTag -eq 'int' -or $isImplicit) -and $value -cmatch $integerPattern) {
        Write-Output -InputObject (ConvertFrom-YamlInteger -Value $value) -NoEnumerate
        return
    }

    if (($standardTag -eq 'float' -or $isImplicit) -and $value -cmatch $infinityPattern) {
        $infinity = if ($value.StartsWith('-', [System.StringComparison]::Ordinal)) {
            [double]::NegativeInfinity
        } else {
            [double]::PositiveInfinity
        }
        Write-Output -InputObject $infinity -NoEnumerate
        return
    }

    if (($standardTag -eq 'float' -or $isImplicit) -and $value -cmatch $nanPattern) {
        Write-Output -InputObject ([double]::NaN) -NoEnumerate
        return
    }

    if (($standardTag -eq 'float' -or $isImplicit) -and $value -cmatch $numberPattern) {
        $number = [double] 0
        $parsed = [double]::TryParse(
            $value,
            [System.Globalization.NumberStyles]::Float,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref] $number
        )
        if (-not $parsed -or [double]::IsInfinity($number)) {
            throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlFloatOverflow' -Message (
                    "The finite YAML floating-point value '$value' is outside the supported range."
                ))
        }
        Write-Output -InputObject $number -NoEnumerate
        return
    }

    if ($standardTag -eq 'binary') {
        try {
            $bytes = [System.Convert]::FromBase64String(($value -replace '\s', ''))
        } catch [System.FormatException] {
            throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlInvalidBinary' -Message (
                    "The value for tag 'tag:yaml.org,2002:binary' is not valid Base64."
                ))
        }
        Write-Output -InputObject $bytes -NoEnumerate
        return
    }

    if ($standardTag -eq 'timestamp') {
        $timestampPattern = '^\d{4}-\d{2}-\d{2}(?:[Tt ]\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:[ \t]*(?:[Zz]|[-+]\d{1,2}(?::?\d{2})?))?)?$'
        if ($value -cnotmatch $timestampPattern) {
            throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlInvalidTimestamp' -Message (
                    "The value '$value' is not a supported YAML timestamp."
                ))
        }

        $date = [datetime]::MinValue
        if ([datetime]::TryParseExact(
                $value,
                'yyyy-MM-dd',
                [System.Globalization.CultureInfo]::InvariantCulture,
                [System.Globalization.DateTimeStyles]::None,
                [ref] $date
            )) {
            Write-Output -InputObject ([datetime]::SpecifyKind($date, [System.DateTimeKind]::Unspecified)) -NoEnumerate
            return
        }

        $normalized = $value -replace '\s+([+-]\d{1,2}(?::?\d{2})?)$', '$1'
        if ($normalized -match '([+-])(\d{1,2})$') {
            $offsetSuffix = '{0}{1}:00' -f $Matches[1], $Matches[2].PadLeft(2, '0')
            $normalized = $normalized.Substring(0, $normalized.Length - $Matches[0].Length) + $offsetSuffix
        } elseif ($normalized -match '([+-])(\d{2})(\d{2})$') {
            $offsetSuffix = '{0}{1}:{2}' -f $Matches[1], $Matches[2], $Matches[3]
            $normalized = $normalized.Substring(0, $normalized.Length - $Matches[0].Length) + $offsetSuffix
        }

        if ($normalized -cmatch '(?:[Zz]|[-+]\d{2}:\d{2})$') {
            $offset = [datetimeoffset]::MinValue
            if ([datetimeoffset]::TryParse(
                    $normalized,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
                    [ref] $offset
                )) {
                Write-Output -InputObject $offset -NoEnumerate
                return
            }
        } else {
            $dateTime = [datetime]::MinValue
            if ([datetime]::TryParse(
                    $normalized,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [System.Globalization.DateTimeStyles]::AllowWhiteSpaces,
                    [ref] $dateTime
                )) {
                Write-Output -InputObject ([datetime]::SpecifyKind($dateTime, [System.DateTimeKind]::Unspecified)) -NoEnumerate
                return
            }
        }

        throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlInvalidTimestamp' -Message (
                "The value '$value' is not a supported YAML timestamp."
            ))
    }

    if (-not $isImplicit -and $standardTag -in @('null', 'bool', 'int', 'float')) {
        throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlInvalidTaggedScalar' -Message (
                "The value '$value' is invalid for YAML tag '$tag'."
            ))
    }

    Write-Output -InputObject $value -NoEnumerate
}
