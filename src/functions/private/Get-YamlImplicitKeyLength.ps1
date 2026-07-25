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
        [pscustomobject] $Context,

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
