function Get-YamlNodeFingerprint {
    <#
        .SYNOPSIS
        Iteratively creates a structural fingerprint for duplicate-key detection.

        .DESCRIPTION
        Produces a stable hash for a YAML node by walking aliases, semantic tags,
        scalar values, sequence items, and sorted mapping entries. The cache and
        active set avoid repeated hashing and reject cyclic mapping keys during
        duplicate-key detection.

        .EXAMPLE
        Get-YamlNodeFingerprint -Node $keyNode -Active ([System.Collections.Generic.HashSet[int]]::new()) `
            -Cache ([System.Collections.Generic.Dictionary[int, string]]::new()) -Hasher ([System.Security.Cryptography.SHA256]::Create())

        Returns a stable hash string for comparing mapping-key candidates.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The YAML node to fingerprint after resolving any alias chain.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # The active node id set that detects cyclic keys during traversal.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[int]] $Active,

        # The memoized node-id to fingerprint map shared across key checks.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[int, string]] $Cache,

        # The hash algorithm used by scalar, sequence, and mapping fingerprints.
        [Parameter(Mandatory)]
        [System.Security.Cryptography.HashAlgorithm] $Hasher
    )

    $root = [pscustomobject]@{ Value = '' }
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{
            Node    = $Node
            Holder  = $root
            State   = 'Start'
            Index   = 0
            Parts   = $null
            Child   = $null
            KeyHash = ''
        })

    while ($stack.Count -gt 0) {
        $frame = $stack.Peek()
        if ($frame.State -eq 'Start') {
            $effective = $frame.Node
            while ($effective.Kind -eq 'Alias') {
                $effective = $effective.Target
            }
            $frame.Node = $effective

            $cached = ''
            if ($Cache.TryGetValue($effective.Id, [ref] $cached)) {
                $frame.Holder.Value = $cached
                [void] $stack.Pop()
                continue
            }
            if (-not $Active.Add($effective.Id)) {
                throw (New-YamlException -Start $effective.Start -End $effective.End `
                        -ErrorId 'YamlCyclicMappingKey' -Message (
                        'A cyclic YAML node cannot be used as a mapping key.'
                    ))
            }

            if ($effective.Kind -eq 'Scalar') {
                $resolved = Resolve-YamlScalar -Node $effective
                $valueFingerprint = Get-YamlScalarFingerprint -Value $resolved.Value -Hasher $Hasher
                $effectiveTag = Get-YamlEffectiveTag -Node $effective -Value $resolved.Value
                $fingerprint = Get-YamlFingerprintHash -Value (
                    'scalar:{0}:{1}:{2}' -f $effectiveTag.Length, $effectiveTag, $valueFingerprint
                ) -Hasher $Hasher
                $Cache[$effective.Id] = $fingerprint
                [void] $Active.Remove($effective.Id)
                $frame.Holder.Value = $fingerprint
                [void] $stack.Pop()
                continue
            }

            $frame.Parts = [System.Collections.Generic.List[string]]::new()
            $frame.State = if ($effective.Kind -eq 'Sequence') {
                'Sequence'
            } else {
                'MappingKey'
            }
            continue
        }

        if ($frame.State -eq 'Sequence') {
            if ($frame.Index -ge $frame.Node.Items.Count) {
                $semanticTag = Get-YamlEffectiveTag -Node $frame.Node -Value $null
                $canonical = 'sequence:{0}:{1}:{2}' -f @(
                    $semanticTag.Length,
                    $semanticTag,
                    ($frame.Parts -join '|')
                )
                $fingerprint = Get-YamlFingerprintHash -Value $canonical -Hasher $Hasher
                $Cache[$frame.Node.Id] = $fingerprint
                [void] $Active.Remove($frame.Node.Id)
                $frame.Holder.Value = $fingerprint
                [void] $stack.Pop()
                continue
            }
            $frame.Child = [pscustomobject]@{ Value = '' }
            $frame.State = 'SequenceValue'
            $stack.Push([pscustomobject]@{
                    Node    = $frame.Node.Items[$frame.Index]
                    Holder  = $frame.Child
                    State   = 'Start'
                    Index   = 0
                    Parts   = $null
                    Child   = $null
                    KeyHash = ''
                })
            continue
        }
        if ($frame.State -eq 'SequenceValue') {
            $frame.Parts.Add($frame.Child.Value)
            $frame.Index++
            $frame.State = 'Sequence'
            continue
        }

        if ($frame.State -eq 'MappingKey') {
            if ($frame.Index -ge $frame.Node.Entries.Count) {
                $frame.Parts.Sort([System.StringComparer]::Ordinal)
                $mappingTag = Get-YamlEffectiveTag -Node $frame.Node -Value $null
                $canonical = 'mapping:{0}:{1}:{2}' -f @(
                    $mappingTag.Length,
                    $mappingTag,
                    ($frame.Parts -join '|')
                )
                $fingerprint = Get-YamlFingerprintHash -Value $canonical -Hasher $Hasher
                $Cache[$frame.Node.Id] = $fingerprint
                [void] $Active.Remove($frame.Node.Id)
                $frame.Holder.Value = $fingerprint
                [void] $stack.Pop()
                continue
            }
            $frame.Child = [pscustomobject]@{ Value = '' }
            $frame.State = 'MappingKeyValue'
            $stack.Push([pscustomobject]@{
                    Node    = $frame.Node.Entries[$frame.Index].Key
                    Holder  = $frame.Child
                    State   = 'Start'
                    Index   = 0
                    Parts   = $null
                    Child   = $null
                    KeyHash = ''
                })
            continue
        }
        if ($frame.State -eq 'MappingKeyValue') {
            $frame.KeyHash = $frame.Child.Value
            $frame.Child = [pscustomobject]@{ Value = '' }
            $frame.State = 'MappingValue'
            $stack.Push([pscustomobject]@{
                    Node    = $frame.Node.Entries[$frame.Index].Value
                    Holder  = $frame.Child
                    State   = 'Start'
                    Index   = 0
                    Parts   = $null
                    Child   = $null
                    KeyHash = ''
                })
            continue
        }
        if ($frame.State -eq 'MappingValue') {
            $frame.Parts.Add(
                (Get-YamlFingerprintHash -Value (
                    "entry:$($frame.KeyHash)=$($frame.Child.Value)"
                ) -Hasher $Hasher)
            )
            $frame.Index++
            $frame.State = 'MappingKey'
        }
    }

    $root.Value
}
