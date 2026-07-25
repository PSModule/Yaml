function Get-YamlNormalizedFloat {
    <#
        .SYNOPSIS
        Normalizes a finite CLR floating-point value to a decimal significand and exponent.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object] $Value
    )

    $culture = [System.Globalization.CultureInfo]::InvariantCulture
    if ($Value -is [decimal]) {
        if ($Value -eq 0) {
            return '0e0'
        }
        $text = $Value.ToString('G29', $culture)
    } elseif ($Value -is [single]) {
        $number = [single] $Value
        if ([single]::IsNaN($number)) {
            return 'nan'
        }
        if ([single]::IsPositiveInfinity($number)) {
            return '+inf'
        }
        if ([single]::IsNegativeInfinity($number)) {
            return '-inf'
        }
        if ($number -eq 0) {
            return '0e0'
        }
        $text = $number.ToString('R', $culture)
    } elseif ($Value -is [double]) {
        $number = [double] $Value
        if ([double]::IsNaN($number)) {
            return 'nan'
        }
        if ([double]::IsPositiveInfinity($number)) {
            return '+inf'
        }
        if ([double]::IsNegativeInfinity($number)) {
            return '-inf'
        }
        if ($number -eq 0) {
            return '0e0'
        }
        $text = $number.ToString('R', $culture)
    } else {
        throw [System.ArgumentException]::new(
            "Type '$($Value.GetType().FullName)' is not a supported floating-point type.",
            'Value'
        )
    }

    $match = [regex]::Match(
        $text,
        '^(?<sign>[-+]?)(?<integer>[0-9]+)(?:\.(?<fraction>[0-9]*))?(?:[eE](?<exponent>[-+]?[0-9]+))?$',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $match.Success) {
        throw [System.InvalidOperationException]::new(
            "The invariant floating-point text '$text' could not be normalized."
        )
    }

    $fraction = $match.Groups['fraction'].Value
    $digits = ($match.Groups['integer'].Value + $fraction).TrimStart('0')
    if ($digits.Length -eq 0) {
        return '0e0'
    }

    $exponent = 0 - $fraction.Length
    if ($match.Groups['exponent'].Success) {
        $exponent += [int]::Parse(
            $match.Groups['exponent'].Value,
            [System.Globalization.NumberStyles]::AllowLeadingSign,
            $culture
        )
    }
    while ($digits.Length -gt 1 -and $digits[$digits.Length - 1].Equals([char] '0')) {
        $digits = $digits.Substring(0, $digits.Length - 1)
        $exponent++
    }

    $sign = if ($match.Groups['sign'].Value.Equals(
            '-',
            [System.StringComparison]::Ordinal
        )) {
        '-'
    } else {
        ''
    }
    return '{0}{1}e{2}' -f $sign, $digits, $exponent
}
