function Read-YamlDocumentByteOrderMark {
    <#
        .SYNOPSIS
        Consumes a byte order mark while scanning an actual document prefix.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Advances an in-memory parser context.'
    )]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [switch] $RequireDocumentStart
    )

    if ($Context.LineIndex -ge $Context.Lines.Count) {
        return
    }
    $index = $Context.LineStarts[$Context.LineIndex]
    $atStreamStart = $index -eq 0
    if (-not $atStreamStart -and
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

    $Context.Text = $Context.Text.Remove($index, 1)
    $Context.Lines[$Context.LineIndex] = $Context.Lines[$Context.LineIndex].Substring(1)
    for ($line = $Context.LineIndex + 1; $line -lt $Context.LineStarts.Count; $line++) {
        $Context.LineStarts[$line]--
    }
}
