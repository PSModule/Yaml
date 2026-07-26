function Merge-YamlRepresentationNode {
    <#
        .SYNOPSIS
        Merges one later YAML representation node into an existing cloned node.

        .DESCRIPTION
        Applies an overlay node to a cloned base node according to merge policies
        for nulls, scalar conflicts, sequences, and mappings. It keeps the merge
        working graph isolated while preserving structural key equality, clone
        identity, indexes, and mutation tracking for subsequent overlays.

        .EXAMPLE
        Merge-YamlRepresentationNode -BaseNode $baseClone -OverlayNode $overlayDocument -SequenceAction Unique -ConflictAction Error -NullAction Ignore -Path '$' -Context $mergeContext

        Merges the overlay document into the cloned base graph, reusing compatible
        nodes and throwing on conflicts.

        .LINK
        https://psmodule.io/Yaml/Functions/Merge-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates only an isolated in-memory merge graph.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The cloned destination node to update so original input graphs remain immutable.
        [Parameter(Mandatory)]
        [pscustomobject] $BaseNode,

        # The later-precedence node to merge into the cloned graph.
        [Parameter(Mandatory)]
        [pscustomobject] $OverlayNode,

        # Selects how compatible sequences are combined when both sides are sequences.
        [Parameter(Mandatory)]
        [ValidateSet('Replace', 'Append', 'Unique')]
        [string] $SequenceAction,

        # Controls whether incompatible kinds/tags or unequal scalars replace or stop the merge.
        [Parameter(Mandatory)]
        [ValidateSet('Replace', 'Error')]
        [string] $ConflictAction,

        # Controls whether overlay nulls intentionally replace or leave prior nodes intact.
        [Parameter(Mandatory)]
        [ValidateSet('Replace', 'Ignore')]
        [string] $NullAction,

        # Carries the current diagnostic location for classified conflict errors.
        [Parameter(Mandatory)]
        [string] $Path,

        # Shared merge context supplies clone caches, indexes, equality state, and budgets.
        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    Add-YamlMergeWork -State $Context.WorkState -Node $OverlayNode `
        -Operation 'representation node merge'

    $base = Get-YamlMergeNode -Node $BaseNode
    $overlay = Get-YamlMergeNode -Node $OverlayNode
    $overlayTag = Get-YamlMergeNodeTag -Node $overlay
    if ($NullAction -eq 'Ignore' -and
        $overlayTag -ceq 'tag:yaml.org,2002:null') {
        Write-Output -InputObject $BaseNode -NoEnumerate
        return
    }

    $baseTag = Get-YamlMergeNodeTag -Node $base
    $isCompatible = $base.Kind -ceq $overlay.Kind -and $baseTag -ceq $overlayTag
    if (-not $isCompatible) {
        if ($ConflictAction -eq 'Error') {
            throw (New-YamlMergeException -Node $overlay -ErrorId 'YamlMergeConflict' -Message (
                    "YAML merge conflict at $Path in input index $($Context.InputIndex), " +
                    "document index $($Context.DocumentIndex): $($base.Kind.ToLowerInvariant()) " +
                    "tag '$baseTag' conflicts with $($overlay.Kind.ToLowerInvariant()) tag '$overlayTag'."
                ))
        }
        return Copy-YamlMergeNode -Node $OverlayNode -Cache $Context.CloneCache `
            -State $Context.CloneState
    }

    if ($base.Kind -eq 'Scalar') {
        if (Test-YamlMergeNodeEqual -Node $base -OtherNode $overlay `
                -State $Context.EqualityState) {
            Write-Output -InputObject $BaseNode -NoEnumerate
            return
        }
        if ($ConflictAction -eq 'Error') {
            throw (New-YamlMergeException -Node $overlay -ErrorId 'YamlMergeConflict' -Message (
                    "YAML merge conflict at $Path in input index $($Context.InputIndex), " +
                    "document index $($Context.DocumentIndex): unequal scalar values use tag '$baseTag'."
                ))
        }
        return Copy-YamlMergeNode -Node $OverlayNode -Cache $Context.CloneCache `
            -State $Context.CloneState
    }

    if ($base.Kind -eq 'Sequence' -and $SequenceAction -eq 'Replace') {
        if (Test-YamlMergeNodeEqual -Node $base -OtherNode $overlay `
                -State $Context.EqualityState) {
            if (-not $Context.CloneCache.ContainsKey($overlay.Id)) {
                $Context.CloneCache[$overlay.Id] = $base
            }
            Write-Output -InputObject $BaseNode -NoEnumerate
            return
        }
        return Copy-YamlMergeNode -Node $OverlayNode -Cache $Context.CloneCache `
            -State $Context.CloneState
    }

    if ($Context.CloneCache.ContainsKey($overlay.Id)) {
        if ($OverlayNode.Kind -eq 'Alias') {
            return Copy-YamlMergeNode -Node $OverlayNode -Cache $Context.CloneCache `
                -State $Context.CloneState
        }
        Write-Output -InputObject $Context.CloneCache[$overlay.Id] -NoEnumerate
        return
    }

    if (Test-YamlMergeNodeEqual -Node $base -OtherNode $overlay `
            -State $Context.EqualityState) {
        $Context.CloneCache[$overlay.Id] = $base
        Write-Output -InputObject $BaseNode -NoEnumerate
        return
    }
    $Context.CloneCache[$overlay.Id] = $base

    if ($base.Kind -eq 'Sequence') {
        if ($SequenceAction -eq 'Append') {
            $changed = $false
            foreach ($item in $overlay.Items) {
                $copy = Copy-YamlMergeNode -Node $item -Cache $Context.CloneCache `
                    -State $Context.CloneState
                $base.Items.Add($copy)
                $changed = $true
            }
            if ($changed) {
                Set-YamlMergeNodeChanged -Node $base -Context $Context
            }
            Write-Output -InputObject $BaseNode -NoEnumerate
            return
        }

        $overlayItems = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($item in $overlay.Items) {
            Add-YamlMergeWork -State $Context.WorkState -Node $item `
                -Operation 'unique overlay candidate identity'
            $effectiveItem = Get-YamlMergeNode -Node $item
            if (-not $overlayItems.Add($effectiveItem.Id)) {
                continue
            }
            $retained = Get-YamlMergeIndex -Node $base -Kind Sequence -Context $Context
            $match = Find-YamlMergeIndexMatch -Index $retained -Node $item -Context $Context
            if ($null -ne $match) {
                continue
            }
            $copy = Copy-YamlMergeNode -Node $item -Cache $Context.CloneCache `
                -State $Context.CloneState
            $base.Items.Add($copy)
            Add-YamlMergeIndexCandidate -Index $retained -Candidate $copy -Context $Context
            Set-YamlMergeNodeChanged -Node $base -Context $Context
        }
        Write-Output -InputObject $BaseNode -NoEnumerate
        return
    }

    for ($index = 0; $index -lt $overlay.Entries.Count; $index++) {
        $overlayEntry = $overlay.Entries[$index]
        $entries = Get-YamlMergeIndex -Node $base -Kind Mapping -Context $Context
        $match = Find-YamlMergeIndexMatch -Index $entries -Node $overlayEntry.Key `
            -Context $Context

        if ($null -ne $match) {
            $childPath = Get-YamlMergePath -Parent $Path -Key $overlayEntry.Key -Index $index
            $previous = $match.Value
            $merged = Merge-YamlRepresentationNode -BaseNode $previous `
                -OverlayNode $overlayEntry.Value -SequenceAction $SequenceAction `
                -ConflictAction $ConflictAction -NullAction $NullAction -Path $childPath `
                -Context $Context
            $match.Value = $merged
            if (-not [object]::ReferenceEquals($previous, $merged)) {
                Set-YamlMergeNodeChanged -Node $base -Context $Context
            }
            continue
        }

        $keyCopy = Copy-YamlMergeNode -Node $overlayEntry.Key -Cache $Context.CloneCache `
            -State $Context.CloneState
        $valueCopy = Copy-YamlMergeNode -Node $overlayEntry.Value -Cache $Context.CloneCache `
            -State $Context.CloneState
        $newEntry = [pscustomobject]@{ Key = $keyCopy; Value = $valueCopy }
        $base.Entries.Add($newEntry)
        Add-YamlMergeIndexCandidate -Index $entries -Candidate $newEntry -Context $Context
        Set-YamlMergeNodeChanged -Node $base -Context $Context
    }

    Write-Output -InputObject $BaseNode -NoEnumerate
}
