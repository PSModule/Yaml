function Get-YamlImplicitKeyLength {
    <#
        .SYNOPSIS
        Gets an implicit key length in Unicode scalar values.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $sourceLength = [Math]::Max(0, $Node.End.Index - $Node.Start.Index)
    return Get-YamlRuneCount -Text $Context.Text.Substring($Node.Start.Index, $sourceLength)
}
