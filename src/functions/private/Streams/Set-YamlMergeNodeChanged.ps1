function Set-YamlMergeNodeChanged {
    <#
        .SYNOPSIS
        Invalidates indexes and equality results affected by a graph mutation.

        .DESCRIPTION
        Marks a mutated node as changed by advancing the mutation version,
        clearing equality cache, and invalidating dependent indexes. This keeps
        later merge comparisons and candidate lookups from reusing stale
        structural results.

        .EXAMPLE
        Set-YamlMergeNodeChanged -Node $baseMapping -Context $mergeContext

        Invalidates cached equality and index data affected by the modified
        mapping node.

        .LINK
        https://psmodule.io/Yaml/Functions/Merge-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Updates only isolated in-memory merge bookkeeping.'
    )]
    [CmdletBinding()]
    param (
        # The mutated node whose dependent merge bookkeeping may now be stale.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # Shared merge context contains mutation state, equality cache, and index dependents.
        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $effective = Get-YamlMergeNode -Node $Node
    Add-YamlMergeWork -State $Context.WorkState -Node $effective `
        -Operation 'mutation invalidation'
    $Context.MutationState.Version = [long] $Context.MutationState.Version + 1
    $Context.EqualityState.Cache.Clear()

    $indexes = $null
    if (-not $Context.IndexDependents.TryGetValue($effective.Id, [ref] $indexes)) {
        return
    }
    foreach ($index in $indexes) {
        Add-YamlMergeWork -State $Context.WorkState -Node $effective `
            -Operation 'dependent index invalidation'
        $index.IsValid = $false
    }
}
