function Get-YamlMergeNode {
    <#
        .SYNOPSIS
        Resolves aliases to their effective YAML representation node.

        .DESCRIPTION
        Follows alias targets until the effective representation node is reached.
        Merge comparison, indexing, and mutation bookkeeping use this canonical
        node so aliases do not create false differences.

        .EXAMPLE
        Get-YamlMergeNode -Node $aliasNode

        Returns the alias target node, or the original node when it is not an
        alias.

        .LINK
        https://psmodule.io/Yaml/Functions/Merge-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The node to canonicalize before merge bookkeeping or comparison.
        [Parameter(Mandatory)]
        [pscustomobject] $Node
    )

    $effective = $Node
    while ($effective.Kind -eq 'Alias') {
        $effective = $effective.Target
    }
    Write-Output -InputObject $effective -NoEnumerate
}
