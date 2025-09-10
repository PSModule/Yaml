
# Helper function to parse a scalar value and return the appropriate type
function Convert-YamlValue {
    param (
        [string]$RawValue
    )
    $trimmed = $RawValue.Trim()
    if ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"')) {
        # Double-quoted string
        return $trimmed.Substring(1, $trimmed.Length - 2)
    } elseif ($trimmed.StartsWith("'") -and $trimmed.EndsWith("'")) {
        # Single-quoted string
        return $trimmed.Substring(1, $trimmed.Length - 2)
    } else {
        # Unquoted value: detect type
        if ($trimmed -eq 'null' -or $trimmed -eq 'Null' -or $trimmed -eq 'NULL' -or $trimmed -eq '') {
            return $null
        } elseif ($trimmed -eq 'true' -or $trimmed -eq 'True' -or $trimmed -eq 'TRUE') {
            return $true
        } elseif ($trimmed -eq 'false' -or $trimmed -eq 'False' -or $trimmed -eq 'FALSE') {
            return $false
        } else {
            $intValue = 0
            if ([int]::TryParse($trimmed, [ref]$intValue)) {
                return $intValue
            }
            $doubleValue = 0.0
            if ([double]::TryParse($trimmed, [ref]$doubleValue)) {
                return $doubleValue
            }
            # If not a number, return as string
            return $trimmed
        }
    }
}
