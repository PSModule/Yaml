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

    if ($Node.Kind.Equals('Scalar', [System.StringComparison]::Ordinal)) {
        return Get-YamlRuneCount -Text ([string] $Node.Value)
    }
    return Get-YamlRuneCount -Text $RenderedText
}
