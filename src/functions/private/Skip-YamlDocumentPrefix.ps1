function Skip-YamlDocumentPrefix {
    <#
        .SYNOPSIS
        Advances across repeated YAML document prefixes.

        .DESCRIPTION
        Repeatedly consumes allowed byte order marks, blank lines, and comments
        before a document body. This keeps the parser context positioned at the
        next content line while enforcing explicit document-start requirements.

        .EXAMPLE
        Skip-YamlDocumentPrefix -Context $context -RequireDocumentStart

        Advances the context line index past prefix trivia before reading the next document.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Advances an in-memory parser context.'
    )]
    [CmdletBinding()]
    param (
        # The reader context whose current line index is advanced over prefixes.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # Requires prefix validation to honor an explicit document-start marker.
        [Parameter()]
        [switch] $RequireDocumentStart
    )

    $validatedPrefix = $false
    do {
        $lineIndex = $Context.LineIndex
        $consumedByteOrderMark = $false
        if ($lineIndex -lt $Context.Lines.Count -and
            $Context.Lines[$lineIndex].StartsWith(
                [string] [char] 0xFEFF,
                [System.StringComparison]::Ordinal
            )) {
            $atStreamStart = $Context.LineStarts[$lineIndex] -eq 0
            if ($atStreamStart -or $validatedPrefix -or
                (Test-YamlDocumentByteOrderMark -Context $Context `
                    -RequireDocumentStart:$RequireDocumentStart)) {
                Read-YamlDocumentByteOrderMark -Context $Context `
                    -RequireDocumentStart:$RequireDocumentStart -SkipValidation
                $consumedByteOrderMark = $true
                if (-not $atStreamStart) {
                    $validatedPrefix = $true
                }
            }
        }
        Skip-YamlBlockTrivia -Context $Context
    } while (
        $Context.LineIndex -ne $lineIndex -or
        $consumedByteOrderMark
    )
}
