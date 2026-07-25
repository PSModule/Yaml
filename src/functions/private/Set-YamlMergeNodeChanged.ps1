function Set-YamlMergeNodeChanged {
    <#
        .SYNOPSIS
        Invalidates indexes and equality results affected by a graph mutation.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Updates only isolated in-memory merge bookkeeping.'
    )]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

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
