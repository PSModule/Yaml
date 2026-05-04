function ConvertFrom-YamlLineStream {
    <#
        .SYNOPSIS
        Splits YAML text into significant lines, dropping comments and blank lines.

        .DESCRIPTION
        Returns an array of `[pscustomobject]` records with `Indent`, `Content`, and `Number` properties.
        - Lines that are empty or whitespace-only are skipped.
        - Lines whose first non-whitespace character is `#` are skipped.
        - Inline comments (` #...` outside quotes) are stripped from the content.
        - Tabs in indentation are not allowed (YAML spec); a terminating error is thrown if one is found.
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

        # Compute indent (spaces before first non-space). Tabs are invalid per YAML spec.
        $indent = 0
        while ($indent -lt $raw.Length -and ($raw[$indent] -eq ' ' -or $raw[$indent] -eq "`t")) {
            if ($raw[$indent] -eq "`t") {
                throw "YAML forbids tab characters in indentation (line $($i + 1)). Use spaces instead."
            }
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
