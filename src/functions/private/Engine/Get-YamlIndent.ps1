function Get-YamlIndent {
    <#
        .SYNOPSIS
        Gets a line's space indentation.

        .DESCRIPTION
        Counts leading space characters in a line and ignores tabs because YAML
        indentation is space-only. Line metadata and context are accepted to keep
        the shared indentation-reader contract consistent.

        .EXAMPLE
        Get-YamlIndent -Line '  name: value' -LineNumber 3 -Context $context

        Returns 2 because the line begins with two spaces.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'Line metadata is part of the shared indentation-reader contract.'
    )]
    [CmdletBinding()]
    [OutputType([int])]
    param (
        # Supplies the source line whose leading spaces define the indentation width.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Line,

        # Preserves the shared reader contract and identifies the measured line.
        [Parameter(Mandatory)]
        [int] $LineNumber,

        # Preserves scanner context in the shared indentation-reader contract.
        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $indent = 0
    while ($indent -lt $Line.Length -and $Line[$indent] -eq ' ') {
        $indent++
    }
    return $indent
}
