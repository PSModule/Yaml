function Add-YamlMergeIndexCandidate {
    <#
        .SYNOPSIS
        Adds one mapping key or sequence item to a structural candidate index.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Index,

        [Parameter(Mandatory)]
        [pscustomobject] $Candidate,

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
