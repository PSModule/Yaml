function Get-YamlImplicitKeyLength {
    <#
        .SYNOPSIS
        Gets an implicit key length in Unicode scalar values.

        .DESCRIPTION
        Measures an implicit key source span in Unicode scalar values rather than
        UTF-16 code units. The parser uses this to enforce YAML's implicit-key
        length rule correctly for non-BMP characters.

        .EXAMPLE
        Get-YamlImplicitKeyLength -Node $keyNode -Context $context -EndIndex $colonIndex

        Returns the key length up to the supplied colon index in Unicode scalar values.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        # Provides the key node start and default end marks used to measure the source span.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # Supplies the complete source text so the measured span can be counted as runes.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # Overrides the node end when the scanner must stop measurement at a delimiter.
        [Parameter()]
        [ValidateRange(0, 2147483647)]
        [int] $EndIndex
    )

    $sourceEnd = if ($PSBoundParameters.ContainsKey('EndIndex')) {
        $EndIndex
    } else {
        $Node.End.Index
    }
    $sourceLength = [Math]::Max(0, $sourceEnd - $Node.Start.Index)
    return Get-YamlRuneCount -Text $Context.Text.Substring($Node.Start.Index, $sourceLength)
}
