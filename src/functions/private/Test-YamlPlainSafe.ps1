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

    # Strings that match YAML 1.2.2 core schema literals must be quoted to preserve string type.
    # Comparison is case-sensitive — only the lowercase canonical forms are recognised by parsers.
    if ($Text -ceq 'true' -or $Text -ceq 'false' -or $Text -ceq 'null' -or $Text -ceq '~') {
        return $false
    }

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
