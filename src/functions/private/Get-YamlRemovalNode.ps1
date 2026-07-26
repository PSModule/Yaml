function Get-YamlRemovalNode {
    <#
        .SYNOPSIS
        Resolves aliases to an effective YAML node with cycle-safe accounting.

        .DESCRIPTION
        Follows alias nodes until it reaches the effective scalar, sequence, or
        mapping node used by removal logic. It records alias traversal work and
        detects alias-only cycles or broken aliases so pointer walks cannot loop
        forever.

        .EXAMPLE
        Get-YamlRemovalNode -Node $entry.Value -State $state

        Returns the non-alias node that removal logic should inspect for the entry value.

        .LINK
        https://psmodule.io/Yaml/Functions/Remove-YamlEntry/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The candidate node may be an alias, so removal needs its effective
        # target before inspecting kind or value.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # The work state charges each alias hop and enforces traversal safety for
        # this invocation.
        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    $effective = $Node
    $visitedAliases = [System.Collections.Generic.HashSet[int]]::new()
    while ($effective.Kind -eq 'Alias') {
        Add-YamlRemovalWork -State $State -Operation 'alias traversal' -Node $effective
        if (-not $visitedAliases.Add($effective.Id)) {
            throw (New-YamlRemovalException -Node $effective `
                    -ErrorId 'YamlRemovalAliasCycle' -Message (
                    'A YAML alias-only cycle cannot be traversed by a removal path.'
                ))
        }
        if ($null -eq $effective.Target) {
            throw (New-YamlRemovalException -Node $effective `
                    -ErrorId 'YamlRemovalInvalidGraph' -Message (
                    'A YAML alias in the removal graph has no target.'
                ))
        }
        $effective = $effective.Target
    }
    Write-Output -InputObject $effective -NoEnumerate
}
