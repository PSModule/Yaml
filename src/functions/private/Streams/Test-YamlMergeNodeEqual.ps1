function Test-YamlMergeNodeEqual {
    <#
        .SYNOPSIS
        Compares YAML representation graphs with collision-safe structural equality.

        .DESCRIPTION
        Compares two YAML representation graphs by effective tags, scalar values,
        sequence order, mapping key equality, and graph identity, resolving aliases
        and cycles safely. It caches results by mutation version so merge indexing
        can verify hash collisions without repeating full comparisons unnecessarily.

        .EXAMPLE
        Test-YamlMergeNodeEqual -Node $retainedKey -OtherNode $overlayKey -State $mergeContext.EqualityState

        Returns true when the retained and overlay keys are structurally equal for
        merge matching.

        .LINK
        https://psmodule.io/Yaml/Functions/Streams/Merge-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # The left representation graph used as the retained comparison side.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # The right representation graph being tested against the retained side.
        [Parameter(Mandatory)]
        [pscustomobject] $OtherNode,

        # Holds equality cache, work budget, and mutation-version context.
        [Parameter(Mandatory)]
        [pscustomobject] $State,

        # Optionally reuses fingerprints for left-side mapping keys during recursive comparison.
        [Parameter()]
        [AllowNull()]
        [System.Collections.Generic.Dictionary[int, string]] $LeftFingerprintCache,

        # Optionally reuses fingerprints for right-side mapping keys during recursive comparison.
        [Parameter()]
        [AllowNull()]
        [System.Collections.Generic.Dictionary[int, string]] $RightFingerprintCache
    )

    if ($null -eq $LeftFingerprintCache) {
        $LeftFingerprintCache = [System.Collections.Generic.Dictionary[int, string]]::new()
    }
    if ($null -eq $RightFingerprintCache) {
        $RightFingerprintCache = [System.Collections.Generic.Dictionary[int, string]]::new()
    }

    $rootLeft = Get-YamlMergeNode -Node $Node
    $rootRight = Get-YamlMergeNode -Node $OtherNode
    $cacheKey = '{0}:{1}:{2}:{3}' -f @(
        $State.MutationState.Version,
        $State.InputIndex,
        $rootLeft.Id,
        $rootRight.Id
    )
    Add-YamlMergeWork -State $State.WorkState -Node $rootRight `
        -Operation 'equality cache lookup'
    $cached = $false
    if ($State.Cache.TryGetValue($cacheKey, [ref] $cached)) {
        return $cached
    }

    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $pending = [System.Collections.Generic.Stack[object]]::new()
    $pending.Push([pscustomobject]@{ Left = $Node; Right = $OtherNode })

    while ($pending.Count -gt 0) {
        $pair = $pending.Pop()
        $left = $pair.Left
        while ($left.Kind -eq 'Alias') {
            Add-YamlMergeWork -State $State.WorkState -Node $left `
                -Operation 'equality alias traversal'
            $left = $left.Target
        }
        $right = $pair.Right
        while ($right.Kind -eq 'Alias') {
            Add-YamlMergeWork -State $State.WorkState -Node $right `
                -Operation 'equality alias traversal'
            $right = $right.Target
        }
        Add-YamlMergeWork -State $State.WorkState -Node $right `
            -Operation 'equality pair comparison'

        $pairId = '{0}:{1}' -f $left.Id, $right.Id
        if (-not $seen.Add($pairId)) {
            continue
        }

        if ($left.Kind -cne $right.Kind) {
            $State.Cache[$cacheKey] = $false
            return $false
        }
        $leftTag = Get-YamlMergeNodeTag -Node $left
        $rightTag = Get-YamlMergeNodeTag -Node $right
        if (-not [string]::Equals(
                $leftTag,
                $rightTag,
                [System.StringComparison]::Ordinal
            )) {
            $State.Cache[$cacheKey] = $false
            return $false
        }

        if ($left.Kind -eq 'Scalar') {
            $leftValue = (Resolve-YamlScalar -Node $left).Value
            $rightValue = (Resolve-YamlScalar -Node $right).Value
            if ($null -eq $leftValue -or $null -eq $rightValue) {
                if ($null -ne $leftValue -or $null -ne $rightValue) {
                    $State.Cache[$cacheKey] = $false
                    return $false
                }
                continue
            }
            if ($leftValue -is [byte[]] -or $rightValue -is [byte[]]) {
                if ($leftValue -isnot [byte[]] -or $rightValue -isnot [byte[]] -or
                    $leftValue.Count -ne $rightValue.Count) {
                    $State.Cache[$cacheKey] = $false
                    return $false
                }
                for ($index = 0; $index -lt $leftValue.Count; $index++) {
                    if ($leftValue[$index] -ne $rightValue[$index]) {
                        $State.Cache[$cacheKey] = $false
                        return $false
                    }
                }
                continue
            }
            if ($leftValue -is [datetimeoffset] -or $leftValue -is [datetime] -or
                $rightValue -is [datetimeoffset] -or $rightValue -is [datetime]) {
                $leftTicks = if ($leftValue -is [datetimeoffset]) {
                    $leftValue.UtcDateTime.Ticks
                } elseif ($leftValue.Kind -eq [System.DateTimeKind]::Local) {
                    $leftValue.ToUniversalTime().Ticks
                } else {
                    $leftValue.Ticks
                }
                $rightTicks = if ($rightValue -is [datetimeoffset]) {
                    $rightValue.UtcDateTime.Ticks
                } elseif ($rightValue.Kind -eq [System.DateTimeKind]::Local) {
                    $rightValue.ToUniversalTime().Ticks
                } else {
                    $rightValue.Ticks
                }
                if ($leftTicks -ne $rightTicks) {
                    $State.Cache[$cacheKey] = $false
                    return $false
                }
                continue
            }
            if ($leftValue -is [decimal] -or $leftValue -is [double] -or
                $leftValue -is [single] -or $rightValue -is [decimal] -or
                $rightValue -is [double] -or $rightValue -is [single]) {
                $leftNumber = Get-YamlNormalizedFloat -Value $leftValue
                $rightNumber = Get-YamlNormalizedFloat -Value $rightValue
                if ($leftNumber -cne $rightNumber) {
                    $State.Cache[$cacheKey] = $false
                    return $false
                }
                continue
            }
            if ($leftValue -is [string] -and $rightValue -is [string]) {
                if (-not $leftValue.Equals($rightValue, [System.StringComparison]::Ordinal)) {
                    $State.Cache[$cacheKey] = $false
                    return $false
                }
                continue
            }
            if ($leftValue -is [bool] -and $rightValue -is [bool]) {
                if ($leftValue -ne $rightValue) {
                    $State.Cache[$cacheKey] = $false
                    return $false
                }
                continue
            }
            $leftText = $leftValue.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $rightText = $rightValue.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            if ($leftText -cne $rightText) {
                $State.Cache[$cacheKey] = $false
                return $false
            }
            continue
        }

        if ($left.Kind -eq 'Sequence') {
            if ($left.Items.Count -ne $right.Items.Count) {
                $State.Cache[$cacheKey] = $false
                return $false
            }
            for ($index = $left.Items.Count - 1; $index -ge 0; $index--) {
                $pending.Push([pscustomobject]@{
                        Left  = $left.Items[$index]
                        Right = $right.Items[$index]
                    })
            }
            continue
        }

        if ($left.Entries.Count -ne $right.Entries.Count) {
            $State.Cache[$cacheKey] = $false
            return $false
        }
        Add-YamlMergeWork -State $State.WorkState -Node $right `
            -Operation 'equality mapping index build'
        $rightEntries = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        $rightIndexedIds = [System.Collections.Generic.HashSet[int]]::new()
        for ($index = 0; $index -lt $right.Entries.Count; $index++) {
            $rightKey = $right.Entries[$index].Key
            Add-YamlMergeWork -State $State.WorkState -Node $rightKey `
                -Operation 'equality mapping candidate identity'
            $effectiveKey = Get-YamlMergeNode -Node $rightKey
            if (-not $rightIndexedIds.Add($effectiveKey.Id)) {
                continue
            }
            $fingerprint = Get-YamlMergeFingerprint -Node $rightKey -State $State `
                -Cache $RightFingerprintCache
            Add-YamlMergeWork -State $State.WorkState -Node $rightKey `
                -Operation 'equality mapping bucket visit'
            $bucket = $null
            if (-not $rightEntries.TryGetValue($fingerprint, [ref] $bucket)) {
                $bucket = [pscustomobject]@{
                    Candidates = [System.Collections.Generic.List[object]]::new()
                }
                $rightEntries[$fingerprint] = $bucket
            }
            Add-YamlMergeWork -State $State.WorkState -Node $rightKey `
                -Operation 'equality mapping candidate visit'
            $bucket.Candidates.Add([pscustomobject]@{
                    Index = $index
                    Entry = $right.Entries[$index]
                })
        }

        $matched = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($leftEntry in $left.Entries) {
            $fingerprint = Get-YamlMergeFingerprint -Node $leftEntry.Key -State $State `
                -Cache $LeftFingerprintCache
            Add-YamlMergeWork -State $State.WorkState -Node $leftEntry.Key `
                -Operation 'equality mapping bucket lookup'
            $bucket = $null
            if (-not $rightEntries.TryGetValue($fingerprint, [ref] $bucket)) {
                $State.Cache[$cacheKey] = $false
                return $false
            }
            $match = $null
            foreach ($candidate in $bucket.Candidates) {
                Add-YamlMergeWork -State $State.WorkState -Node $leftEntry.Key `
                    -Operation 'equality mapping candidate comparison'
                if ($matched.Contains($candidate.Index)) {
                    continue
                }
                if (Test-YamlMergeNodeEqual -Node $leftEntry.Key `
                        -OtherNode $candidate.Entry.Key -State $State `
                        -LeftFingerprintCache $LeftFingerprintCache `
                        -RightFingerprintCache $RightFingerprintCache) {
                    $match = $candidate
                    break
                }
            }
            if ($null -eq $match) {
                $State.Cache[$cacheKey] = $false
                return $false
            }
            [void] $matched.Add($match.Index)
            $pending.Push([pscustomobject]@{
                    Left  = $leftEntry.Value
                    Right = $match.Entry.Value
                })
        }
    }

    $State.Cache[$cacheKey] = $true
    return $true
}
