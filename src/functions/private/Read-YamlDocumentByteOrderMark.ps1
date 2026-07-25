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

        [switch] $RequireDocumentStart,

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
