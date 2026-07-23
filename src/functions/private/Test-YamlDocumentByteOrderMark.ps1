function Test-YamlDocumentByteOrderMark {
    <#
        .SYNOPSIS
        Tests for a byte order mark at the current document boundary.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

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
