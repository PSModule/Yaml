function ConvertFrom-YamlFrontmatter {
    <#
        .SYNOPSIS
        Extracts YAML frontmatter from a string when present, otherwise returns the string unchanged.

        .DESCRIPTION
        If the input begins with a `---` line, returns the content between the opening
        `---` and the next `---` or `...` line. Anything after the closing delimiter
        (typically markdown body) is discarded.

        If no frontmatter delimiter is detected, the original input is returned.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    # Normalize line endings for matching.
    $normalized = $Text -replace "`r`n", "`n"
    $lines = $normalized -split "`n"

    # Find first non-empty line.
    $firstIdx = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim().Length -gt 0) {
            $firstIdx = $i
            break
        }
    }

    if ($firstIdx -lt 0) {
        return $Text
    }

    if ($lines[$firstIdx].Trim() -ne '---') {
        return $Text
    }

    # Find closing delimiter.
    for ($j = $firstIdx + 1; $j -lt $lines.Count; $j++) {
        $trim = $lines[$j].Trim()
        if ($trim -eq '---' -or $trim -eq '...') {
            $body = $lines[($firstIdx + 1)..($j - 1)] -join "`n"
            return $body
        }
    }

    # No closing delimiter — treat everything after opening as frontmatter.
    if ($firstIdx + 1 -lt $lines.Count) {
        return ($lines[($firstIdx + 1)..($lines.Count - 1)] -join "`n")
    }
    return ''
}
