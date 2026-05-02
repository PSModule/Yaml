function Remove-YamlInlineComment {
    <#
        .SYNOPSIS
        Removes an unquoted `# comment` suffix from a YAML content line.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'This function operates on a string parameter, not system state.')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line
    )

    $inSingle = $false
    $inDouble = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($c -eq '\' -and $inDouble) {
            # Skip escaped char inside double quotes.
            $i++
            continue
        }
        if ($c -eq "'" -and -not $inDouble) {
            $inSingle = -not $inSingle
            continue
        }
        if ($c -eq '"' -and -not $inSingle) {
            $inDouble = -not $inDouble
            continue
        }
        if ($c -eq '#' -and -not $inSingle -and -not $inDouble) {
            # Comment must be preceded by whitespace or be at start of line.
            if ($i -eq 0 -or $Line[$i - 1] -eq ' ' -or $Line[$i - 1] -eq "`t") {
                return $Line.Substring(0, $i)
            }
        }
    }
    return $Line
}
