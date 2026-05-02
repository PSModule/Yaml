function ConvertFrom-YamlLineStream {
    <#
        .SYNOPSIS
        Splits YAML text into significant lines, dropping comments and blank lines.

        .DESCRIPTION
        Returns an array of `[pscustomobject]` records with `Indent`, `Content`, and `Number` properties.
        - Lines that are empty or whitespace-only are skipped.
        - Lines whose first non-whitespace character is `#` are skipped.
        - Inline comments (` #...` outside quotes) are stripped from the content.
        - Tabs in indentation are not allowed (YAML spec); they are treated as one space here.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '',
        Justification = 'Comma-unary operator preserves List type; PSScriptAnalyzer misdetects as Object[].')]
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[pscustomobject]])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $result = [System.Collections.Generic.List[pscustomobject]]::new()
    $normalized = $Text -replace "`r`n", "`n"
    $rawLines = $normalized -split "`n"

    for ($i = 0; $i -lt $rawLines.Count; $i++) {
        $raw = $rawLines[$i]

        if ([string]::IsNullOrWhiteSpace($raw)) {
            continue
        }

        # Compute indent (spaces before first non-space).
        $indent = 0
        while ($indent -lt $raw.Length -and ($raw[$indent] -eq ' ' -or $raw[$indent] -eq "`t")) {
            $indent++
        }

        $content = $raw.Substring($indent)

        if ($content.StartsWith('#')) {
            continue
        }

        # Strip inline comments while respecting single/double quotes.
        $stripped = Remove-YamlInlineComment -Line $content
        if ([string]::IsNullOrWhiteSpace($stripped)) {
            continue
        }

        # Skip YAML document markers: --- (start) and ... (end).
        $trimmed = $stripped.Trim()
        if ($trimmed -eq '---' -or $trimmed -eq '...') {
            continue
        }

        $result.Add([pscustomobject]@{
                Indent  = $indent
                Content = $stripped.TrimEnd()
                Number  = $i + 1
            })
    }

    return , $result
}

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
