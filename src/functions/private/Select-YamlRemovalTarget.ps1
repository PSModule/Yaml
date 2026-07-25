function Select-YamlRemovalTarget {
    <#
        .SYNOPSIS
        Coalesces duplicate targets and drops fully subsumed descendants.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Targets,

        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    $coalesced = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($target in $Targets) {
        Add-YamlRemovalWork -State $State -Operation 'target coalescing' -Node $target.Node
        if ($coalesced.ContainsKey($target.Key)) {
            $coalesced[$target.Key].AncestorSets.Add([string[]] $target.Ancestors)
            continue
        }

        $ancestorSets = [System.Collections.Generic.List[object]]::new()
        $ancestorSets.Add([string[]] $target.Ancestors)
        $coalesced[$target.Key] = [pscustomobject]@{
            Key           = $target.Key
            Kind          = $target.Kind
            Parent        = $target.Parent
            Index         = $target.Index
            Edge          = $target.Edge
            Node          = $target.Node
            Depth         = $target.Depth
            AncestorSets  = $ancestorSets
            Pointer       = $target.Pointer
            DocumentIndex = $target.DocumentIndex
        }
    }

    $selectedKeys = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($key in $coalesced.Keys) {
        [void] $selectedKeys.Add($key)
    }

    $survivors = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $coalesced.Values) {
        $allRequestsSubsumed = $true
        foreach ($ancestorSet in $candidate.AncestorSets) {
            $requestSubsumed = $false
            foreach ($ancestorKey in $ancestorSet) {
                Add-YamlRemovalWork -State $State -Operation 'ancestor coalescing' `
                    -Node $candidate.Node
                if ($selectedKeys.Contains($ancestorKey)) {
                    $requestSubsumed = $true
                    break
                }
            }
            if (-not $requestSubsumed) {
                $allRequestsSubsumed = $false
                break
            }
        }
        if (-not $allRequestsSubsumed) {
            $survivors.Add($candidate)
        }
    }

    return New-YamlValueBox -Value ([object[]] $survivors.ToArray())
}
