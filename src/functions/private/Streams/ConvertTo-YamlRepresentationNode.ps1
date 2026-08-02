function ConvertTo-YamlRepresentationNode {
    <#
        .SYNOPSIS
        Converts one representation graph to a lossless emission graph.

        .DESCRIPTION
        Copies a parsed representation graph into the emission graph shape expected
        by the writer while preserving node identity, tags, anchors, and aliases.
        It assigns deterministic anchor names so formatted YAML remains stable.

        .EXAMPLE
        ConvertTo-YamlRepresentationNode -Node $document.Root -State $emissionState

        Returns an emission node graph for the representation document.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The representation graph root that must be copied for emission.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # Carries anchor numbering so names stay unique across emitted documents.
        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    $orderedNodes = [System.Collections.Generic.List[object]]::new()
    $visited = [System.Collections.Generic.HashSet[int]]::new()
    $aliasTargets = [System.Collections.Generic.HashSet[int]]::new()
    $pending = [System.Collections.Generic.Stack[object]]::new()
    $pending.Push($Node)

    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        if ($current.Kind -eq 'Alias') {
            [void] $aliasTargets.Add($current.Target.Id)
            if (-not $visited.Contains($current.Target.Id)) {
                $pending.Push($current.Target)
            }
            continue
        }
        if (-not $visited.Add($current.Id)) {
            continue
        }

        $orderedNodes.Add($current)
        if ($current.Kind -eq 'Sequence') {
            for ($index = $current.Items.Count - 1; $index -ge 0; $index--) {
                $pending.Push($current.Items[$index])
            }
        } elseif ($current.Kind -eq 'Mapping') {
            for ($index = $current.Entries.Count - 1; $index -ge 0; $index--) {
                $pending.Push($current.Entries[$index].Value)
                $pending.Push($current.Entries[$index].Key)
            }
        }
    }

    $anchorNames = [System.Collections.Generic.Dictionary[int, string]]::new()
    foreach ($source in $orderedNodes) {
        if (-not [string]::IsNullOrEmpty($source.Anchor) -or
            $aliasTargets.Contains($source.Id)) {
            $anchorNames[$source.Id] = 'id{0:d3}' -f $State.NextAnchor
            $State.NextAnchor++
        }
    }

    $nodes = [System.Collections.Generic.Dictionary[int, object]]::new()
    foreach ($source in $orderedNodes) {
        $target = New-YamlEmissionNode -Kind $source.Kind
        $target.Tag = [string] $source.Tag
        $target.HasUnknownTag = [bool] $source.HasUnknownTag
        if ($anchorNames.ContainsKey($source.Id)) {
            $target.Anchor = $anchorNames[$source.Id]
            $target.ReferenceId = [long] $source.Id
        }

        if ($source.Kind -eq 'Scalar') {
            $target.Value = [string] $source.Value
            $target.Style = 'DoubleQuoted'
            if ([string]::IsNullOrEmpty($source.Tag) -and
                -not $source.HasUnknownTag -and $source.IsPlainImplicit) {
                $resolved = (Resolve-YamlScalar -Node $source).Value
                $effectiveTag = Get-YamlEffectiveTag -Node $source -Value $resolved
                if ($effectiveTag -cne 'tag:yaml.org,2002:str') {
                    $target.Style = 'Plain'
                }
            }
        }
        $nodes[$source.Id] = $target
    }

    foreach ($source in $orderedNodes) {
        $target = $nodes[$source.Id]
        if ($source.Kind -eq 'Sequence') {
            foreach ($item in $source.Items) {
                $itemId = if ($item.Kind -eq 'Alias') {
                    $item.Target.Id
                } else {
                    $item.Id
                }
                $target.Items.Add($nodes[$itemId])
            }
        } elseif ($source.Kind -eq 'Mapping') {
            foreach ($entry in $source.Entries) {
                $keyId = if ($entry.Key.Kind -eq 'Alias') {
                    $entry.Key.Target.Id
                } else {
                    $entry.Key.Id
                }
                $valueId = if ($entry.Value.Kind -eq 'Alias') {
                    $entry.Value.Target.Id
                } else {
                    $entry.Value.Id
                }
                $target.Entries.Add([pscustomobject]@{
                        Key   = $nodes[$keyId]
                        Value = $nodes[$valueId]
                    })
            }
        }
    }

    Write-Output -InputObject $nodes[$Node.Id] -NoEnumerate
}
