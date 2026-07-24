function Skip-YamlDocumentPrefix {
    <#
        .SYNOPSIS
        Advances across repeated YAML document prefixes.
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

    do {
        $lineIndex = $Context.LineIndex
        $textLength = $Context.Text.Length
        Read-YamlDocumentByteOrderMark -Context $Context `
            -RequireDocumentStart:$RequireDocumentStart
        Skip-YamlBlockTrivia -Context $Context
    } while (
        $Context.LineIndex -ne $lineIndex -or
        $Context.Text.Length -ne $textLength
    )
}
