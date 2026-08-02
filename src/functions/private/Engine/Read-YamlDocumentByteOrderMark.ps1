function Read-YamlDocumentByteOrderMark {
    <#
        .SYNOPSIS
        Consumes a byte order mark while scanning an actual document prefix.

        .DESCRIPTION
        Removes leading byte order mark characters from the current physical
        line only when the parser is positioned at an allowed document prefix.
        The stream reader uses it to support BOMs without mutating source text.

        .EXAMPLE
        Read-YamlDocumentByteOrderMark -Context $context -RequireDocumentStart

        Advances the current line start past an allowed document-prefix marker.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Advances an in-memory parser context.'
    )]
    [CmdletBinding()]
    param (
        # Parser context whose current line and line-start offset may advance.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # Requires noninitial BOMs to be attached to an explicit document start.
        [Parameter()]
        [switch] $RequireDocumentStart,

        # Skips the location check when the caller has already validated it.
        [Parameter()]
        [switch] $SkipValidation
    )

    if ($Context.LineIndex -ge $Context.Lines.Count) {
        return
    }
    $index = $Context.LineStarts[$Context.LineIndex]
    $atStreamStart = $index -eq 0
    if (-not $atStreamStart -and -not $SkipValidation -and
        -not (Test-YamlDocumentByteOrderMark -Context $Context `
                -RequireDocumentStart:$RequireDocumentStart)) {
        return
    }
    if (-not $Context.Lines[$Context.LineIndex].StartsWith(
            [string] [char] 0xFEFF,
            [System.StringComparison]::Ordinal
        )) {
        return
    }

    $line = $Context.Lines[$Context.LineIndex]
    $count = 0
    while ($count -lt $line.Length -and $line[$count] -ceq [char] 0xFEFF) {
        $count++
    }

    # Keep the source immutable and advance only this line's physical source offset.
    $Context.Lines[$Context.LineIndex] = $line.Substring($count)
    $Context.LineStarts[$Context.LineIndex] += $count
}
