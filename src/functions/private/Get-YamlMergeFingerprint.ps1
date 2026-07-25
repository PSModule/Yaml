function Get-YamlMergeFingerprint {
    <#
        .SYNOPSIS
        Creates a deterministic structural candidate index for merge comparisons.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [pscustomobject] $State,

        [Parameter()]
        [AllowNull()]
        [System.Collections.Generic.Dictionary[int, string]] $Cache,

        [Parameter()]
        [AllowNull()]
        [pscustomobject] $CandidateIndex
    )

    if ($null -eq $Cache) {
        $Cache = [System.Collections.Generic.Dictionary[int, string]]::new()
    }
    $active = [System.Collections.Generic.HashSet[int]]::new()
    $root = [pscustomobject]@{ Value = ''; IsContextual = $false }
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{
            Node         = $Node
            Holder       = $root
            State        = 'Start'
            Index        = 0
            Parts        = $null
            Child        = $null
            KeyHash      = ''
            Accumulator  = $null
            IsContextual = $false
        })

    while ($stack.Count -gt 0) {
        $frame = $stack.Peek()
        if ($frame.State -eq 'Start') {
            $effective = $frame.Node
            while ($effective.Kind -eq 'Alias') {
                Add-YamlMergeWork -State $State.WorkState -Node $effective `
                    -Operation 'fingerprint alias traversal'
                $effective = $effective.Target
            }
            Add-YamlMergeWork -State $State.WorkState -Node $effective `
                -Operation 'fingerprint node traversal'
            $frame.Node = $effective

            if ($null -ne $CandidateIndex -and
                $CandidateIndex.Dependencies.Add($effective.Id)) {
                $dependents = $null
                if (-not $State.IndexDependents.TryGetValue(
                        $effective.Id,
                        [ref] $dependents
                    )) {
                    $dependents = [System.Collections.Generic.List[object]]::new()
                    $State.IndexDependents[$effective.Id] = $dependents
                }
                $dependents.Add($CandidateIndex)
            }

            $cached = ''
            if ($Cache.TryGetValue($effective.Id, [ref] $cached)) {
                $frame.Holder.Value = $cached
                [void] $stack.Pop()
                continue
            }

            if (-not $active.Add($effective.Id)) {
                $tag = Get-YamlMergeNodeTag -Node $effective
                $count = if ($effective.Kind -eq 'Sequence') {
                    $effective.Items.Count
                } elseif ($effective.Kind -eq 'Mapping') {
                    $effective.Entries.Count
                } else {
                    0
                }
                $frame.Holder.Value = Get-YamlFingerprintHash -Value (
                    'cycle:{0}:{1}:{2}:{3}' -f @(
                        $effective.Kind.ToLowerInvariant(),
                        $tag.Length,
                        $tag,
                        $count
                    )
                ) -Hasher $State.FingerprintHasher
                $frame.Holder.IsContextual = $true
                [void] $stack.Pop()
                continue
            }

            if ($effective.Kind -eq 'Scalar') {
                $resolved = (Resolve-YamlScalar -Node $effective).Value
                $tag = Get-YamlEffectiveTag -Node $effective -Value $resolved
                $value = Get-YamlScalarFingerprint -Value $resolved `
                    -Hasher $State.FingerprintHasher
                $fingerprint = Get-YamlFingerprintHash -Value (
                    'scalar:{0}:{1}:{2}' -f $tag.Length, $tag, $value
                ) -Hasher $State.FingerprintHasher
                $Cache[$effective.Id] = $fingerprint
                [void] $active.Remove($effective.Id)
                $frame.Holder.Value = $fingerprint
                [void] $stack.Pop()
                continue
            }

            if ($effective.Kind -eq 'Sequence') {
                $frame.Parts = [System.Collections.Generic.List[string]]::new()
                $frame.State = 'Sequence'
            } else {
                $frame.Accumulator = [int[]]::new(32)
                $frame.State = 'MappingKey'
            }
            continue
        }

        if ($frame.State -eq 'Sequence') {
            if ($frame.Index -ge $frame.Node.Items.Count) {
                $tag = Get-YamlEffectiveTag -Node $frame.Node -Value $null
                $canonical = if ($frame.IsContextual) {
                    'cyclic-sequence:{0}:{1}:{2}' -f @(
                        $tag.Length,
                        $tag,
                        $frame.Node.Items.Count
                    )
                } else {
                    'sequence:{0}:{1}:{2}' -f $tag.Length, $tag, ($frame.Parts -join '|')
                }
                $fingerprint = Get-YamlFingerprintHash -Value $canonical `
                    -Hasher $State.FingerprintHasher
                if (-not $frame.IsContextual) {
                    $Cache[$frame.Node.Id] = $fingerprint
                }
                [void] $active.Remove($frame.Node.Id)
                $frame.Holder.Value = $fingerprint
                $frame.Holder.IsContextual = $frame.IsContextual
                [void] $stack.Pop()
                continue
            }
            Add-YamlMergeWork -State $State.WorkState -Node $frame.Node `
                -Operation 'fingerprint sequence entry'
            $frame.Child = [pscustomobject]@{ Value = ''; IsContextual = $false }
            $frame.State = 'SequenceValue'
            $stack.Push([pscustomobject]@{
                    Node         = $frame.Node.Items[$frame.Index]
                    Holder       = $frame.Child
                    State        = 'Start'
                    Index        = 0
                    Parts        = $null
                    Child        = $null
                    KeyHash      = ''
                    Accumulator  = $null
                    IsContextual = $false
                })
            continue
        }
        if ($frame.State -eq 'SequenceValue') {
            $frame.Parts.Add($frame.Child.Value)
            $frame.IsContextual = $frame.IsContextual -or $frame.Child.IsContextual
            $frame.Index++
            $frame.State = 'Sequence'
            continue
        }

        if ($frame.State -eq 'MappingKey') {
            if ($frame.Index -ge $frame.Node.Entries.Count) {
                $tag = Get-YamlEffectiveTag -Node $frame.Node -Value $null
                $canonical = if ($frame.IsContextual) {
                    'cyclic-mapping:{0}:{1}:{2}' -f @(
                        $tag.Length,
                        $tag,
                        $frame.Node.Entries.Count
                    )
                } else {
                    $aggregate = [byte[]]::new($frame.Accumulator.Count)
                    for ($index = 0; $index -lt $aggregate.Count; $index++) {
                        $aggregate[$index] = [byte] $frame.Accumulator[$index]
                    }
                    'mapping:{0}:{1}:{2}:{3}' -f @(
                        $tag.Length,
                        $tag,
                        $frame.Node.Entries.Count,
                        [System.Convert]::ToBase64String($aggregate)
                    )
                }
                $fingerprint = Get-YamlFingerprintHash -Value $canonical `
                    -Hasher $State.FingerprintHasher
                if (-not $frame.IsContextual) {
                    $Cache[$frame.Node.Id] = $fingerprint
                }
                [void] $active.Remove($frame.Node.Id)
                $frame.Holder.Value = $fingerprint
                $frame.Holder.IsContextual = $frame.IsContextual
                [void] $stack.Pop()
                continue
            }
            Add-YamlMergeWork -State $State.WorkState -Node $frame.Node `
                -Operation 'fingerprint mapping entry'
            $frame.Child = [pscustomobject]@{ Value = ''; IsContextual = $false }
            $frame.State = 'MappingKeyValue'
            $stack.Push([pscustomobject]@{
                    Node         = $frame.Node.Entries[$frame.Index].Key
                    Holder       = $frame.Child
                    State        = 'Start'
                    Index        = 0
                    Parts        = $null
                    Child        = $null
                    KeyHash      = ''
                    Accumulator  = $null
                    IsContextual = $false
                })
            continue
        }
        if ($frame.State -eq 'MappingKeyValue') {
            $frame.KeyHash = $frame.Child.Value
            $frame.IsContextual = $frame.IsContextual -or $frame.Child.IsContextual
            $frame.Child = [pscustomobject]@{ Value = ''; IsContextual = $false }
            $frame.State = 'MappingValue'
            $stack.Push([pscustomobject]@{
                    Node         = $frame.Node.Entries[$frame.Index].Value
                    Holder       = $frame.Child
                    State        = 'Start'
                    Index        = 0
                    Parts        = $null
                    Child        = $null
                    KeyHash      = ''
                    Accumulator  = $null
                    IsContextual = $false
                })
            continue
        }
        if ($frame.State -eq 'MappingValue') {
            Add-YamlMergeWork -State $State.WorkState -Node $frame.Node `
                -Operation 'fingerprint mapping combination'
            $entryHash = Get-YamlFingerprintHash -Value (
                "entry:$($frame.KeyHash)=$($frame.Child.Value)"
            ) -Hasher $State.FingerprintHasher
            $entryBytes = [System.Convert]::FromBase64String($entryHash)
            for ($index = 0; $index -lt $entryBytes.Count; $index++) {
                $frame.Accumulator[$index] = (
                    $frame.Accumulator[$index] + $entryBytes[$index]
                ) -band 0xff
            }
            $frame.IsContextual = $frame.IsContextual -or $frame.Child.IsContextual
            $frame.Index++
            $frame.State = 'MappingKey'
        }
    }

    $root.Value
}
