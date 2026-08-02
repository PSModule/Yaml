function ConvertTo-YamlNode {
    <#
        .SYNOPSIS
        Iteratively normalizes a supported PowerShell value to an emission graph.

        .DESCRIPTION
        Walks a supported PowerShell object graph without recursion and produces
        the internal emission nodes consumed by the YAML writer. The state object
        enforces resource limits, reference identity, anchors, and duplicate-key checks.

        .EXAMPLE
        ConvertTo-YamlNode -Value $inputObject -State $serializationState -Depth 1 -EnumsAsStrings

        Returns the root emission node for the input object graph, using enum names when requested.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The PowerShell value that needs a YAML-safe emission representation.
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

        # Carries serialization limits, reference tracking, and shared caches.
        [Parameter(Mandatory)]
        [pscustomobject] $State,

        # Current graph depth used to enforce the configured maximum depth.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth,

        # Allows enum values to be emitted by name instead of underlying number.
        [Parameter()]
        [switch] $EnumsAsStrings
    )

    $root = [pscustomobject]@{ Value = $null }
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{
            Value        = $Value
            Depth        = $Depth
            Holder       = $root
            State        = 'Start'
            Shape        = $null
            Node         = $null
            ReferenceId  = [long] 0
            Index        = 0
            Child        = $null
            KeyNode      = $null
            Fingerprints = $null
            Reserved     = $false
        })

    while ($stack.Count -gt 0) {
        $frame = $stack.Peek()
        if ($frame.State -eq 'Start') {
            if ($frame.Depth -gt $State.MaxDepth) {
                throw (New-YamlSerializationException -ErrorId 'YamlDepthExceeded' -Message (
                        "The object graph exceeds the configured depth limit of $($State.MaxDepth)."
                    ))
            }
            if ($frame.Reserved) {
                $State.ReservedNodeCount--
            }
            $State.NodeCount++
            if ($State.NodeCount -gt $State.MaxNodes) {
                throw (New-YamlSerializationException -ErrorId 'YamlNodeLimitExceeded' -Message (
                        "The object graph exceeds the configured limit of $($State.MaxNodes) nodes."
                    ))
            }

            $isReference = Test-YamlSerializationReference -Value $frame.Value
            if ($isReference) {
                $firstTime = $false
                $frame.ReferenceId = $State.IdGenerator.GetId($frame.Value, [ref] $firstTime)
                if (-not $firstTime) {
                    $State.ReferenceCounts[$frame.ReferenceId]++
                    if ($State.Active.Contains($frame.ReferenceId)) {
                        throw (New-YamlSerializationException -ErrorId 'YamlCycleDetected' -Message (
                                "A cycle was detected while serializing type '$($frame.Value.GetType().FullName)'."
                            ))
                    }
                    $frame.Holder.Value = $State.NodesById[$frame.ReferenceId]
                    [void] $stack.Pop()
                    continue
                }
                $State.ReferenceCounts[$frame.ReferenceId] = 1
                $State.ReferenceOrder.Add($frame.ReferenceId)
            }

            $frame.Shape = Get-YamlSerializationShape -Value $frame.Value -State $State `
                -EnumsAsStrings:$EnumsAsStrings
            if ($frame.Shape.Kind -eq 'Scalar') {
                $frame.Holder.Value = $frame.Shape.Node
                [void] $stack.Pop()
                continue
            }

            if ($frame.Shape.Kind -eq 'Binary') {
                $frame.Shape.Node.ReferenceId = $frame.ReferenceId
                $State.NodesById[$frame.ReferenceId] = $frame.Shape.Node
                $frame.Holder.Value = $frame.Shape.Node
                [void] $stack.Pop()
                continue
            }

            $frame.Node = New-YamlEmissionNode -Kind $frame.Shape.Kind
            $frame.Node.ReferenceId = $frame.ReferenceId
            $State.NodesById[$frame.ReferenceId] = $frame.Node
            $frame.Holder.Value = $frame.Node
            [void] $State.Active.Add($frame.ReferenceId)
            if ($frame.Shape.Kind -eq 'Mapping') {
                $frame.Fingerprints = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::Ordinal
                )
                $frame.State = 'MappingKey'
            } else {
                $frame.State = 'Sequence'
            }
            continue
        }

        if ($frame.State -eq 'Sequence') {
            if ($frame.Index -ge $frame.Shape.Values.Count) {
                [void] $State.Active.Remove($frame.ReferenceId)
                [void] $stack.Pop()
                continue
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'SequenceValue'
            $stack.Push([pscustomobject]@{
                    Value        = [object] $frame.Shape.Values[$frame.Index]
                    Depth        = $frame.Depth + 1
                    Holder       = $frame.Child
                    State        = 'Start'
                    Shape        = $null
                    Node         = $null
                    ReferenceId  = [long] 0
                    Index        = 0
                    Child        = $null
                    KeyNode      = $null
                    Fingerprints = $null
                    Reserved     = $true
                })
            continue
        }
        if ($frame.State -eq 'SequenceValue') {
            $frame.Node.Items.Add($frame.Child.Value)
            $frame.Index++
            $frame.State = 'Sequence'
            continue
        }

        if ($frame.State -eq 'MappingKey') {
            if ($frame.Index -ge $frame.Shape.Values.Count) {
                [void] $State.Active.Remove($frame.ReferenceId)
                [void] $stack.Pop()
                continue
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'MappingKeyValue'
            $stack.Push([pscustomobject]@{
                    Value        = [object] $frame.Shape.Values[$frame.Index].Key
                    Depth        = $frame.Depth + 1
                    Holder       = $frame.Child
                    State        = 'Start'
                    Shape        = $null
                    Node         = $null
                    ReferenceId  = [long] 0
                    Index        = 0
                    Child        = $null
                    KeyNode      = $null
                    Fingerprints = $null
                    Reserved     = $true
                })
            continue
        }
        if ($frame.State -eq 'MappingKeyValue') {
            $frame.KeyNode = $frame.Child.Value
            $fingerprint = Get-YamlEmissionNodeFingerprint -Node $frame.KeyNode `
                -Cache $State.Fingerprints `
                -Active ([System.Collections.Generic.HashSet[long]]::new()) `
                -Hasher $State.FingerprintHasher
            if (-not $frame.Fingerprints.Add($fingerprint)) {
                throw (New-YamlSerializationException -ErrorId 'YamlDuplicateKey' -Message (
                        'Two mapping keys normalize to the same YAML value.'
                    ))
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'MappingValue'
            $stack.Push([pscustomobject]@{
                    Value        = [object] $frame.Shape.Values[$frame.Index].Value
                    Depth        = $frame.Depth + 1
                    Holder       = $frame.Child
                    State        = 'Start'
                    Shape        = $null
                    Node         = $null
                    ReferenceId  = [long] 0
                    Index        = 0
                    Child        = $null
                    KeyNode      = $null
                    Fingerprints = $null
                    Reserved     = $true
                })
            continue
        }
        if ($frame.State -eq 'MappingValue') {
            $frame.Node.Entries.Add([pscustomobject]@{
                    Key   = $frame.KeyNode
                    Value = $frame.Child.Value
                })
            $frame.Index++
            $frame.State = 'MappingKey'
        }
    }

    $root.Value
}
