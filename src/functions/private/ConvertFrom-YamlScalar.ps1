function ConvertFrom-YamlScalar {
    <#
        .SYNOPSIS
        Converts a raw YAML scalar token into the appropriate PowerShell type.
    #>
    [CmdletBinding()]
    [OutputType([string], [bool], [int], [long], [double])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Raw
    )

    $value = $Raw.Trim()

    if ($value.Length -eq 0) { return $null }

    # Quoted strings.
    if ($value.Length -ge 2 -and $value.StartsWith("'") -and $value.EndsWith("'")) {
        $inner = $value.Substring(1, $value.Length - 2)
        return ($inner -replace "''", "'")
    }
    if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
        $inner = $value.Substring(1, $value.Length - 2)
        return (Expand-YamlDoubleQuoted -Text $inner)
    }

    # Null literal (YAML 1.2.2 core schema): empty, ~, null only. Case-sensitive.
    if ($value -ceq '~' -or $value -ceq 'null') { return $null }

    # Boolean literal (YAML 1.2.2 core schema): true / false only. Case-sensitive.
    if ($value -ceq 'true') { return $true }
    if ($value -ceq 'false') { return $false }

    # Integer.
    $intVal = 0
    if ([int]::TryParse($value, [System.Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref] $intVal)) {
        return $intVal
    }
    $longVal = [long]0
    if ([long]::TryParse($value, [System.Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref] $longVal)) {
        return $longVal
    }

    # Float.
    # Reject .NET-specific special float tokens that are not part of the YAML 1.2.2 core schema.
    # Core schema uses .inf/.Inf/.INF/.nan/.NaN/.NAN (dot-prefix form). The bare NaN/Infinity
    # words are accepted by [double]::TryParse but must remain plain strings per the spec.
    if ($value -imatch '^[+-]?(infinity|nan)$') { return $value }
    $dblVal = 0.0
    if ([double]::TryParse($value, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref] $dblVal)) {
        return $dblVal
    }

    # Plain string.
    return $value
}
