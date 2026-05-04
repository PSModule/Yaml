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
    $inPlain  = $false
    for ($i = 0; $i -lt $Line.Length; $i++) {
        $c = $Line[$i]
        if ($c -eq '\' -and $inDouble) {
            # Skip escaped char inside double quotes.
            $i++
            continue
        }
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
        if ($c -eq '#' -and -not $inSingle -and -not $inDouble) {
            # Comment must be preceded by whitespace or be at start of line.
            if ($i -eq 0 -or $Line[$i - 1] -eq ' ' -or $Line[$i - 1] -eq "`t") {
                return $Line.Substring(0, $i)
            }
        }
        # Track plain scalar vs token boundary.
        if (-not $inSingle -and -not $inDouble -and -not $inPlain) {
            if ($c -ne ' ' -and $c -ne "`t") {
                # A '- ' sequence dash is a token boundary, not a plain scalar start.
                if ($c -eq '-' -and $i + 1 -lt $Line.Length -and $Line[$i + 1] -eq ' ') {
                    # sequence dash — value after '- ' may be quoted; do not enter plain
                } else {
                    $inPlain = $true
                }
            }
        }
        # Reset $inPlain after mapping separator ': ' to allow value-position quotes.
        if ($c -eq ':' -and -not $inSingle -and -not $inDouble -and $i + 1 -lt $Line.Length) {
            $next = $Line[$i + 1]
            if ($next -eq ' ' -or $next -eq "`t") {
                $inPlain = $false
            }
        }
    }
    return $Line
}
