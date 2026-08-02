function Find-YamlMergeIndexMatch {
    <#
        .SYNOPSIS
        Finds a collision-safe structural match in a YAML merge candidate index.

        .DESCRIPTION
        Looks up a node's structural fingerprint in a candidate index and verifies
        any bucket collisions with full graph equality. This makes mapping-key and
        unique-sequence matching fast without trusting hashes as equality.

        .EXAMPLE
        Find-YamlMergeIndexMatch -Index $retainedIndex -Node $overlayEntry.Key -Context $mergeContext

        Returns the matching retained entry when the overlay key is structurally
        equal, or nothing when no match exists.

        .LINK
        https://psmodule.io/Yaml/Functions/Merge-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The retained candidate index narrows possible structural matches.
        [Parameter(Mandatory)]
        [pscustomobject] $Index,

        # The overlay key or sequence item to match against retained candidates.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # Shared merge context supplies fingerprint caches, equality state, and work limits.
        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $fingerprint = Get-YamlMergeFingerprint -Node $Node -State $Context.EqualityState `
        -Cache $Context.OverlayFingerprintCache
    Add-YamlMergeWork -State $Context.WorkState -Node $Node -Operation 'index bucket lookup'

    $bucket = $null
    if (-not $Index.Buckets.TryGetValue($fingerprint, [ref] $bucket)) {
        return
    }

    foreach ($candidate in $bucket.Candidates) {
        $candidateNode = if ($Index.Kind -eq 'Mapping') {
            $candidate.Key
        } else {
            $candidate
        }
        Add-YamlMergeWork -State $Context.WorkState -Node $Node `
            -Operation 'index candidate comparison'
        if (Test-YamlMergeNodeEqual -Node $candidateNode -OtherNode $Node `
                -State $Context.EqualityState) {
            Write-Output -InputObject $candidate -NoEnumerate
            return
        }
    }
}
