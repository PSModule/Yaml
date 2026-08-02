function Get-YamlMergeIndex {
    <#
        .SYNOPSIS
        Gets or rebuilds a mutation-aware structural candidate index.

        .DESCRIPTION
        Retrieves the cached structural candidate index for a mapping or sequence,
        rebuilding it when mutations invalidated prior buckets. It lets recursive
        merge operations reuse fingerprint buckets while remaining correct after
        graph changes.

        .EXAMPLE
        Get-YamlMergeIndex -Node $baseMapping -Kind Mapping -Context $mergeContext

        Returns a valid mapping index for matching overlay keys against retained
        entries.

        .LINK
        https://psmodule.io/Yaml/Functions/Streams/Merge-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The mapping or sequence node whose retained candidates need indexing.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # Selects whether entries or items are indexed for this node.
        [Parameter(Mandatory)]
        [ValidateSet('Mapping', 'Sequence')]
        [string] $Kind,

        # Provides index caches, dependency tracking, and work accounting.
        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $effective = Get-YamlMergeNode -Node $Node
    $cache = if ($Kind -eq 'Mapping') {
        $Context.MappingIndexes
    } else {
        $Context.SequenceIndexes
    }

    $index = $null
    if (-not $cache.TryGetValue($effective.Id, [ref] $index)) {
        $index = [pscustomobject]@{
            Kind                = $Kind
            IsValid             = $false
            Buckets             = [System.Collections.Generic.Dictionary[string, object]]::new(
                [System.StringComparer]::Ordinal
            )
            Dependencies        = [System.Collections.Generic.HashSet[int]]::new()
            FingerprintCache    = [System.Collections.Generic.Dictionary[int, string]]::new()
            IndexedEffectiveIds = [System.Collections.Generic.HashSet[int]]::new()
        }
        $cache[$effective.Id] = $index
    }

    if ($index.IsValid) {
        Write-Output -InputObject $index -NoEnumerate
        return
    }

    Add-YamlMergeWork -State $Context.WorkState -Node $effective -Operation 'index rebuild'
    $index.Buckets.Clear()
    $index.FingerprintCache.Clear()
    $index.IndexedEffectiveIds.Clear()
    $candidates = if ($Kind -eq 'Mapping') {
        $effective.Entries
    } else {
        $effective.Items
    }
    foreach ($candidate in $candidates) {
        Add-YamlMergeIndexCandidate -Index $index -Candidate $candidate -Context $Context
    }
    $index.IsValid = $true

    Write-Output -InputObject $index -NoEnumerate
}
