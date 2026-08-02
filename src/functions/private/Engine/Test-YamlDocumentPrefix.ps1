function Test-YamlDocumentPrefix {
    <#
        .SYNOPSIS
        Tests whether text after a BOM is a legal YAML document prefix.

        .DESCRIPTION
        Walks the text after a document-boundary byte order mark, skipping blank
        lines, comments, and allowed leading BOMs. The scanner uses it to decide
        whether a BOM can start a document or must be rejected.

        .EXAMPLE
        Test-YamlDocumentPrefix -Text "$([char]0xFEFF)---`nname: value" -Index 1 -RequireDocumentStart

        Returns true because the prefix after the BOM begins with a document-start marker.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # Supplies the complete stream text because the legal prefix can span lines.
        [Parameter(Mandatory)]
        [string] $Text,

        # Marks the zero-based offset immediately after the BOM being validated.
        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [int] $Index,

        # Forces validation to accept only prefixes that lead to an explicit document start.
        [Parameter()]
        [switch] $RequireDocumentStart
    )

    $directiveSeen = $false
    while ($Index -lt $Text.Length) {
        if ($Text[$Index] -ceq [char] 0xFEFF) {
            $Index++
            continue
        }
        $lineEnd = $Text.IndexOf("`n", $Index, [System.StringComparison]::Ordinal)
        if ($lineEnd -lt 0) {
            $lineEnd = $Text.Length
        }
        $line = $Text.Substring($Index, $lineEnd - $Index)
        $trimmed = $line.TrimStart(' ', "`t")
        if ($trimmed.Length -eq 0 -or
            $trimmed.StartsWith('#', [System.StringComparison]::Ordinal)) {
            if ($lineEnd -ge $Text.Length) {
                return -not $directiveSeen
            }
            $Index = $lineEnd + 1
            continue
        }
        if ($line.StartsWith('%', [System.StringComparison]::Ordinal) -and
            -not $RequireDocumentStart) {
            $directiveSeen = $true
            if ($lineEnd -ge $Text.Length) {
                return $false
            }
            $Index = $lineEnd + 1
            continue
        }
        if ($line.StartsWith('---', [System.StringComparison]::Ordinal) -and
            ($line.Length -eq 3 -or (Test-YamlWhiteSpace -Character $line[3]))) {
            return $true
        }
        return -not $RequireDocumentStart -and -not $directiveSeen
    }
    return -not $directiveSeen
}
