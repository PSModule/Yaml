function Get-YamlEmissionImplicitKeyLength {
    <#
        .SYNOPSIS
        Gets an emitted implicit key length in Unicode scalar values.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [string] $RenderedText
    )

    return Get-YamlRuneCount -Text $RenderedText
}
