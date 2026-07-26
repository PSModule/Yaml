function Remove-YamlRepresentationTarget {
    <#
        .SYNOPSIS
        Applies resolved YAML removal targets in stable mutation order.

        .DESCRIPTION
        Mutates the cloned document list and container nodes for previously
        resolved removal targets. It groups and sorts targets deepest-first and
        descending by index so removing documents, sequence items, and mapping
        entries does not shift later mutations.

        .EXAMPLE
        Remove-YamlRepresentationTarget -Documents $documents -Targets $targets -State $state

        Detaches the resolved document, sequence, and mapping targets from the cloned representation graph.

        .LINK
        https://psmodule.io/Yaml/Functions/Remove-YamlEntry/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates only an isolated in-memory representation graph.'
    )]
    [CmdletBinding()]
    param (
        # The cloned document list is mutated when a target removes an entire
        # YAML document.
        [Parameter(Mandatory)]
        [System.Collections.Generic.List[object]] $Documents,

        # The resolved targets identify exact document, sequence, or mapping
        # edges to detach.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Targets,

        # The work state charges ordering and mutation steps so transaction
        # application is budgeted.
        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    if ($Targets.Count -eq 0) {
        return
    }
    Add-YamlRemovalWork -State $State -Count $Targets.Count -Operation 'target ordering'
    $groups = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($target in $Targets) {
        $groupKey = if ($target.Kind -ceq 'Document') {
            'Documents'
        } else {
            "Node:$($target.Parent.Id)"
        }
        if (-not $groups.ContainsKey($groupKey)) {
            $groups[$groupKey] = [pscustomobject]@{
                Key     = $groupKey
                Depth   = [int] $target.Depth
                Targets = [System.Collections.Generic.List[object]]::new()
            }
        } elseif ($target.Depth -gt $groups[$groupKey].Depth) {
            $groups[$groupKey].Depth = [int] $target.Depth
        }
        $groups[$groupKey].Targets.Add($target)
    }
    $orderedGroups = @(
        $groups.Values | Sort-Object -Property @(
            @{ Expression = { [int] $_.Depth }; Descending = $true }
            @{ Expression = { [string] $_.Key }; Ascending = $true }
        )
    )

    foreach ($group in $orderedGroups) {
        $orderedTargets = @(
            $group.Targets | Sort-Object -Property @(
                @{ Expression = { [int] $_.Index }; Descending = $true }
                @{ Expression = { [string] $_.Kind }; Ascending = $true }
            )
        )
        foreach ($target in $orderedTargets) {
            Add-YamlRemovalWork -State $State -Operation 'target mutation' -Node $target.Node
            if ($target.Kind -ceq 'Document') {
                if ($target.Index -ge $Documents.Count -or -not [object]::ReferenceEquals(
                        $Documents[$target.Index],
                        $target.Node
                    )) {
                    throw (New-YamlRemovalException -Node $target.Node `
                            -ErrorId 'YamlRemovalMutationConflict' -Message (
                            'A resolved YAML document target changed before mutation.'
                        ))
                }
                $Documents.RemoveAt($target.Index)
                continue
            }

            if ($target.Kind -ceq 'Sequence') {
                if ($target.Index -ge $target.Parent.Items.Count -or
                    -not [object]::ReferenceEquals(
                        $target.Parent.Items[$target.Index],
                        $target.Edge
                    )) {
                    throw (New-YamlRemovalException -Node $target.Node `
                            -ErrorId 'YamlRemovalMutationConflict' -Message (
                            'A resolved YAML sequence target changed before mutation.'
                        ))
                }
                $target.Parent.Items.RemoveAt($target.Index)
                continue
            }

            if ($target.Index -ge $target.Parent.Entries.Count -or
                -not [object]::ReferenceEquals(
                    $target.Parent.Entries[$target.Index],
                    $target.Edge
                )) {
                throw (New-YamlRemovalException -Node $target.Node `
                        -ErrorId 'YamlRemovalMutationConflict' -Message (
                        'A resolved YAML mapping target changed before mutation.'
                    ))
            }
            $target.Parent.Entries.RemoveAt($target.Index)
        }
    }
}
