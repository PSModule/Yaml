function Get-YamlIndent {
    <#
        .SYNOPSIS
        Gets a line's space indentation.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Line metadata is part of the shared indentation-reader contract.'
    )]
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line,

        [Parameter(Mandatory)]
        [int] $LineNumber,

        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $indent = 0
    while ($indent -lt $Line.Length -and $Line[$indent] -eq ' ') {
        $indent++
    }
    return $indent
}
