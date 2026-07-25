function Find-YamlMergeIndexMatch {
    <#
        .SYNOPSIS
        Finds a collision-safe structural match in a YAML merge candidate index.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Index,

        [Parameter(Mandatory)]
        [pscustomobject] $Node,

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
