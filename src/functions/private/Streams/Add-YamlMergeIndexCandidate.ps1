function Add-YamlMergeIndexCandidate {
    <#
        .SYNOPSIS
        Adds one mapping key or sequence item to a structural candidate index.

        .DESCRIPTION
        Adds a mapping entry or sequence item to an index bucket keyed by a
        structural fingerprint. It tracks effective node identities and
        dependencies so later mutations can invalidate only indexes that may be
        stale.

        .EXAMPLE
        Add-YamlMergeIndexCandidate -Index $mappingIndex -Candidate $entry -Context $mergeContext

        Indexes the entry's key as a candidate for future structural equality
        lookups.

        .LINK
        https://psmodule.io/Yaml/Functions/Merge-Yaml/
    #>
    [CmdletBinding()]
    param (
        # The candidate index receiving the mapping key or sequence item.
        [Parameter(Mandatory)]
        [pscustomobject] $Index,

        # The entry or item to index for later structural equality lookup.
        [Parameter(Mandatory)]
        [pscustomobject] $Candidate,

        # Shared merge context provides work accounting and fingerprint/equality state.
        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $node = if ($Index.Kind -eq 'Mapping') {
        $Candidate.Key
    } else {
        $Candidate
    }
    Add-YamlMergeWork -State $Context.WorkState -Node $node `
        -Operation 'index candidate identity'
    $effective = Get-YamlMergeNode -Node $node
    if (-not $Index.IndexedEffectiveIds.Add($effective.Id)) {
        return
    }

    $fingerprint = Get-YamlMergeFingerprint -Node $node -State $Context.EqualityState `
        -Cache $Index.FingerprintCache -CandidateIndex $Index

    Add-YamlMergeWork -State $Context.WorkState -Node $node -Operation 'index bucket visit'
    $bucket = $null
    if (-not $Index.Buckets.TryGetValue($fingerprint, [ref] $bucket)) {
        $bucket = [pscustomobject]@{
            Candidates = [System.Collections.Generic.List[object]]::new()
        }
        $Index.Buckets[$fingerprint] = $bucket
    }

    Add-YamlMergeWork -State $Context.WorkState -Node $node -Operation 'index candidate visit'
    $bucket.Candidates.Add($Candidate)
}
