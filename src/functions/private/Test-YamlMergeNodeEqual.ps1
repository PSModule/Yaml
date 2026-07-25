function Test-YamlMergeNodeEqual {
    <#
        .SYNOPSIS
        Compares YAML representation graphs with collision-safe structural equality.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [pscustomobject] $OtherNode,

        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    $seen = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $pending = [System.Collections.Generic.Stack[object]]::new()
    $pending.Push([pscustomobject]@{ Left = $Node; Right = $OtherNode })

    while ($pending.Count -gt 0) {
        $pair = $pending.Pop()
        $left = Get-YamlMergeNode -Node $pair.Left
        $right = Get-YamlMergeNode -Node $pair.Right
        $pairId = '{0}:{1}' -f $left.Id, $right.Id
        if (-not $seen.Add($pairId)) {
            continue
        }

        $State.EqualityCount++
        if ($State.EqualityCount -gt $State.MaxNodes) {
            throw (New-YamlMergeException -Node $right -ErrorId 'YamlMergeEqualityLimitExceeded' -Message (
                    "YAML structural equality exceeded the configured limit of $($State.MaxNodes) node pairs."
                ))
        }

        if ($left.Kind -cne $right.Kind) {
            return $false
        }
        $leftTag = Get-YamlMergeNodeTag -Node $left
        $rightTag = Get-YamlMergeNodeTag -Node $right
        if ($leftTag -cne $rightTag) {
            return $false
        }

        if ($left.Kind -eq 'Scalar') {
            $leftValue = (Resolve-YamlScalar -Node $left).Value
            $rightValue = (Resolve-YamlScalar -Node $right).Value
            if ($null -eq $leftValue -or $null -eq $rightValue) {
                if ($null -ne $leftValue -or $null -ne $rightValue) {
                    return $false
                }
                continue
            }
            if ($leftValue -is [byte[]] -or $rightValue -is [byte[]]) {
                if ($leftValue -isnot [byte[]] -or $rightValue -isnot [byte[]] -or
                    $leftValue.Count -ne $rightValue.Count) {
                    return $false
                }
                for ($index = 0; $index -lt $leftValue.Count; $index++) {
                    if ($leftValue[$index] -ne $rightValue[$index]) {
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
                    return $false
                }
                continue
            }
            if ($leftValue -is [string] -and $rightValue -is [string]) {
                if (-not $leftValue.Equals($rightValue, [System.StringComparison]::Ordinal)) {
                    return $false
                }
                continue
            }
            if ($leftValue -is [bool] -and $rightValue -is [bool]) {
                if ($leftValue -ne $rightValue) {
                    return $false
                }
                continue
            }
            $leftText = $leftValue.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            $rightText = $rightValue.ToString([System.Globalization.CultureInfo]::InvariantCulture)
            if ($leftText -cne $rightText) {
                return $false
            }
            continue
        }

        if ($left.Kind -eq 'Sequence') {
            if ($left.Items.Count -ne $right.Items.Count) {
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
            return $false
        }
        $rightEntries = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        for ($index = 0; $index -lt $right.Entries.Count; $index++) {
            $fingerprint = Get-YamlMergeFingerprint -Node $right.Entries[$index].Key -State $State
            if (-not $rightEntries.ContainsKey($fingerprint)) {
                $rightEntries[$fingerprint] = [System.Collections.Generic.List[object]]::new()
            }
            $rightEntries[$fingerprint].Add([pscustomobject]@{
                    Index = $index
                    Entry = $right.Entries[$index]
                })
        }
        $matched = [System.Collections.Generic.HashSet[int]]::new()
        foreach ($leftEntry in $left.Entries) {
            $fingerprint = Get-YamlMergeFingerprint -Node $leftEntry.Key -State $State
            if (-not $rightEntries.ContainsKey($fingerprint)) {
                return $false
            }
            $match = $null
            foreach ($candidate in $rightEntries[$fingerprint]) {
                if ($matched.Contains($candidate.Index)) {
                    continue
                }
                if (Test-YamlMergeNodeEqual -Node $leftEntry.Key -OtherNode $candidate.Entry.Key `
                        -State $State) {
                    $match = $candidate
                    break
                }
            }
            if ($null -eq $match) {
                return $false
            }
            [void] $matched.Add($match.Index)
            $pending.Push([pscustomobject]@{
                    Left  = $leftEntry.Value
                    Right = $match.Entry.Value
                })
        }
    }

    return $true
}
