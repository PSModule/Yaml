function Find-YamlMappingColon {
    <#
        .SYNOPSIS
        Returns the index of the unquoted `:` separator in a content line, or -1 if not found.

        .DESCRIPTION
        The colon must be followed by whitespace or end-of-line for it to be a YAML mapping
        separator. Colons inside quoted strings are ignored.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Content
    )

    $inSingle = $false
    $inDouble = $false
    for ($i = 0; $i -lt $Content.Length; $i++) {
        $c = $Content[$i]
        if ($c -eq '\' -and $inDouble) { $i++; continue }
        if ($c -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle; continue }
        if ($c -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble; continue }
        if ($c -eq ':' -and -not $inSingle -and -not $inDouble) {
            if ($i -eq $Content.Length - 1) { return $i }
            $next = $Content[$i + 1]
            if ($next -eq ' ' -or $next -eq "`t") { return $i }
        }
    }
    return -1
}
