function Find-YamlMappingColon {
    <#
        .SYNOPSIS
        Returns the index of the unquoted `:` separator in a content line, or -1 if not found.

        .DESCRIPTION
        The colon must be followed by whitespace or end-of-line for it to be a YAML mapping
        separator. Colons inside quoted strings are ignored. Quote characters inside plain
        (unquoted) scalars are treated as literal characters and do not toggle quote state.
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
    $inPlain  = $false
    for ($i = 0; $i -lt $Content.Length; $i++) {
        $c = $Content[$i]
        if ($c -eq '\' -and $inDouble) { $i++; continue }
        if ($c -eq "'" -and -not $inDouble) {
            if ($inSingle) { $inSingle = $false; continue }
            if (-not $inPlain) { $inSingle = $true; continue }
            continue
        }
        if ($c -eq '"' -and -not $inSingle) {
            if ($inDouble) { $inDouble = $false; continue }
            if (-not $inPlain) { $inDouble = $true; continue }
            continue
        }
        if ($c -eq ':' -and -not $inSingle -and -not $inDouble) {
            if ($i -eq $Content.Length - 1) { return $i }
            $next = $Content[$i + 1]
            if ($next -eq ' ' -or $next -eq "`t") { return $i }
        }
        if (-not $inSingle -and -not $inDouble -and -not $inPlain) {
            if ($c -ne ' ' -and $c -ne "`t") {
                $inPlain = $true
            }
        }
    }
    return -1
}
