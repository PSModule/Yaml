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
            $coalesced[$target.Key].PathSets.Add([string[]] $target.Path)
            continue
        }

        $pathSets = [System.Collections.Generic.List[object]]::new()
        $pathSets.Add([string[]] $target.Path)
        $coalesced[$target.Key] = [pscustomobject]@{
            Key           = $target.Key
            Kind          = $target.Kind
            Parent        = $target.Parent
            Index         = $target.Index
            Edge          = $target.Edge
            Node          = $target.Node
            Depth         = $target.Depth
            PathSets      = $pathSets
            Pointer       = $target.Pointer
            DocumentIndex = $target.DocumentIndex
        }
    }

    $pathRoot = [pscustomobject]@{
        Children   = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        TargetKeys = [System.Collections.Generic.HashSet[string]]::new(
            [System.StringComparer]::Ordinal
        )
    }
    foreach ($target in $coalesced.Values) {
        foreach ($path in $target.PathSets) {
            $pathNode = $pathRoot
            foreach ($edgeKey in $path) {
                Add-YamlRemovalWork -State $State -Operation 'target path indexing' `
                    -Node $target.Node
                if (-not $pathNode.Children.ContainsKey($edgeKey)) {
                    $pathNode.Children[$edgeKey] = [pscustomobject]@{
                        Children   = [System.Collections.Generic.Dictionary[string, object]]::new(
                            [System.StringComparer]::Ordinal
                        )
                        TargetKeys = [System.Collections.Generic.HashSet[string]]::new(
                            [System.StringComparer]::Ordinal
                        )
                    }
                }
                $pathNode = $pathNode.Children[$edgeKey]
            }
            [void] $pathNode.TargetKeys.Add($target.Key)
        }
    }

    $survivors = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in $coalesced.Values) {
        $allRequestsSubsumed = $true
        foreach ($path in $candidate.PathSets) {
            $requestSubsumed = $false
            $pathNode = $pathRoot
            for ($pathIndex = 0; $pathIndex -lt $path.Count - 1; $pathIndex++) {
                Add-YamlRemovalWork -State $State -Operation 'target path ancestry' `
                    -Node $candidate.Node
                $edgeKey = $path[$pathIndex]
                if (-not $pathNode.Children.ContainsKey($edgeKey)) {
                    break
                }
                $pathNode = $pathNode.Children[$edgeKey]
                if ($pathNode.TargetKeys.Count -gt 1 -or
                    ($pathNode.TargetKeys.Count -eq 1 -and
                    -not $pathNode.TargetKeys.Contains($candidate.Key))) {
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
