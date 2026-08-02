function Get-YamlEmissionNodeFingerprint {
    <#
        .SYNOPSIS
        Iteratively fingerprints a normalized emission node.

        .DESCRIPTION
        Walks scalar, sequence, and mapping emission nodes without recursion to create a stable
        digest for a normalized YAML node. The serializer uses the digest to detect structurally
        identical values and decide when an anchor can be reused or a cycle must be reported.

        .EXAMPLE
        Get-YamlEmissionNodeFingerprint -Node $node -Cache $fingerprintCache -Active $activeReferences -Hasher $sha256

        Returns the stable fingerprint used to compare the normalized emission node with other nodes.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The normalized node is fingerprinted so anchors can be deduplicated safely.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # Previously fingerprinted reference IDs are reused to avoid hashing shared nodes twice.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[long, string]] $Cache,

        # Active reference IDs detect cycles while the graph is being fingerprinted.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[long]] $Active,

        # The reusable hash algorithm keeps every nested fingerprint on the same digest scheme.
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
            $hasReferenceId = $frame.Node.ReferenceId -ne 0
            $cached = ''
            if ($hasReferenceId -and
                $Cache.TryGetValue($frame.Node.ReferenceId, [ref] $cached)) {
                $frame.Holder.Value = $cached
                [void] $stack.Pop()
                continue
            }
            if ($hasReferenceId -and -not $Active.Add($frame.Node.ReferenceId)) {
                throw (New-YamlSerializationException -ErrorId 'YamlCycleDetected' -Message (
                        'A cycle was detected while fingerprinting a YAML mapping key.'
                    ))
            }

            if ($frame.Node.Kind -eq 'Scalar') {
                $isPlainImplicit = [string]::IsNullOrEmpty($frame.Node.Tag) -and
                $frame.Node.Style -eq 'Plain'
                $mark = New-YamlMark -Index 0 -Line 0 -Column 0
                $resolved = Resolve-YamlScalar -Node ([pscustomobject]@{
                        Tag              = $frame.Node.Tag
                        HasUnknownTag    = $false
                        Value            = $frame.Node.Value
                        IsPlainImplicit  = $isPlainImplicit
                        Start            = $mark
                        End              = $mark
                        ResolutionState  = 0
                        ResolvedValue    = $null
                        MaxNumericLength = 1048576
                    })
                $valueFingerprint = Get-YamlScalarFingerprint -Value $resolved.Value -Hasher $Hasher
                $effectiveTag = Get-YamlEffectiveTag -Node $frame.Node -Value $resolved.Value
                $fingerprint = Get-YamlFingerprintHash -Value (
                    'scalar:{0}:{1}:{2}' -f $effectiveTag.Length, $effectiveTag, $valueFingerprint
                ) -Hasher $Hasher
                if ($hasReferenceId) {
                    $Cache[$frame.Node.ReferenceId] = $fingerprint
                    [void] $Active.Remove($frame.Node.ReferenceId)
                }
                $frame.Holder.Value = $fingerprint
                [void] $stack.Pop()
                continue
            }

            $frame.Parts = [System.Collections.Generic.List[string]]::new()
            $frame.State = if ($frame.Node.Kind -eq 'Sequence') {
                'Sequence'
            } else {
                'MappingKey'
            }
            continue
        }

        if ($frame.State -eq 'Sequence') {
            if ($frame.Index -ge $frame.Node.Items.Count) {
                $effectiveTag = Get-YamlEffectiveTag -Node $frame.Node -Value $null
                $fingerprint = Get-YamlFingerprintHash -Value (
                    'sequence:{0}:{1}:{2}' -f @(
                        $effectiveTag.Length,
                        $effectiveTag,
                        ($frame.Parts -join '|')
                    )
                ) -Hasher $Hasher
                if ($frame.Node.ReferenceId -ne 0) {
                    $Cache[$frame.Node.ReferenceId] = $fingerprint
                    [void] $Active.Remove($frame.Node.ReferenceId)
                }
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
                $effectiveTag = Get-YamlEffectiveTag -Node $frame.Node -Value $null
                $fingerprint = Get-YamlFingerprintHash -Value (
                    'mapping:{0}:{1}:{2}' -f @(
                        $effectiveTag.Length,
                        $effectiveTag,
                        ($frame.Parts -join '|')
                    )
                ) -Hasher $Hasher
                if ($frame.Node.ReferenceId -ne 0) {
                    $Cache[$frame.Node.ReferenceId] = $fingerprint
                    [void] $Active.Remove($frame.Node.ReferenceId)
                }
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
