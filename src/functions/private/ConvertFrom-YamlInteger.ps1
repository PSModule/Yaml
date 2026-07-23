function ConvertFrom-YamlInteger {
    <#
        .SYNOPSIS
        Constructs the narrowest supported numeric value from a YAML integer.
    #>
    [CmdletBinding()]
    [OutputType([int], [long], [System.Numerics.BigInteger])]
    param (
        [Parameter(Mandatory)]
        [string] $Value
    )

    $sign = [System.Numerics.BigInteger]::One
    $digits = $Value
    $base = 10

    if ($digits.StartsWith('+', [System.StringComparison]::Ordinal)) {
        $digits = $digits.Substring(1)
    } elseif ($digits.StartsWith('-', [System.StringComparison]::Ordinal)) {
        $sign = [System.Numerics.BigInteger]::MinusOne
        $digits = $digits.Substring(1)
    }

    if ($digits.StartsWith('0o', [System.StringComparison]::Ordinal)) {
        $base = 8
        $digits = $digits.Substring(2)
    } elseif ($digits.StartsWith('0x', [System.StringComparison]::Ordinal)) {
        $base = 16
        $digits = $digits.Substring(2)
    }

    if ($base -eq 10) {
        $signedDigits = if ($sign -lt 0) { "-$digits" } else { $digits }
        $result = [System.Numerics.BigInteger]::Zero
        if (-not [System.Numerics.BigInteger]::TryParse(
                $signedDigits,
                [System.Globalization.NumberStyles]::Integer,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref] $result
            )) {
            throw [System.FormatException]::new("The YAML integer '$Value' is invalid.")
        }
    } else {
        $result = [System.Numerics.BigInteger]::Zero
        foreach ($character in $digits.ToCharArray()) {
            if ($character -ge [char] '0' -and $character -le [char] '9') {
                $digit = [int] $character - [int] [char] '0'
            } else {
                $digit = 10 + ([int] [char]::ToUpperInvariant($character) - [int] [char] 'A')
            }
            $result = ($result * $base) + $digit
        }
        $result *= $sign
    }

    if ($result -ge [int]::MinValue -and $result -le [int]::MaxValue) {
        return [int] $result
    }
    if ($result -ge [long]::MinValue -and $result -le [long]::MaxValue) {
        return [long] $result
    }
    return $result
}
