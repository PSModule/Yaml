function Test-YamlDocumentByteOrderMark {
    <#
        .SYNOPSIS
        Tests for a byte order mark at the current document boundary.

        .DESCRIPTION
        Detects U+FEFF at the scanner's current line and verifies that the following
        text forms a legal document prefix. This lets the parser distinguish allowed
        document-boundary BOMs from stray byte order marks inside content.

        .EXAMPLE
        Test-YamlDocumentByteOrderMark -Context $context -RequireDocumentStart

        Returns true when the current line begins with a BOM followed by a legal document start.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # Provides scanner state so the helper can inspect the current line and stream text.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # Requires the text after a BOM to contain an explicit document-start marker.
        [Parameter()]
        [switch] $RequireDocumentStart
    )

    if ($Context.LineIndex -ge $Context.Lines.Count -or
        -not $Context.Lines[$Context.LineIndex].StartsWith(
            [string] [char] 0xFEFF,
            [System.StringComparison]::Ordinal
        )) {
        return $false
    }
    return Test-YamlDocumentPrefix -Text $Context.Text `
        -Index ($Context.LineStarts[$Context.LineIndex] + 1) `
        -RequireDocumentStart:$RequireDocumentStart
}
