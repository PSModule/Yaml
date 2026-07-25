function Get-YamlRemovalNode {
    <#
        .SYNOPSIS
        Resolves aliases to an effective YAML node with cycle-safe accounting.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

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
