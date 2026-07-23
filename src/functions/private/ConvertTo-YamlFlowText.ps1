function ConvertTo-YamlFlowText {
    <#
        .SYNOPSIS
        Iteratively renders one emission graph in flow form.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[long]] $EmittedReferences
    )

    $root = [pscustomobject]@{ Value = '' }
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{
            Node    = $Node
            Holder  = $root
            State   = 'Start'
            Index   = 0
            Prefix  = ''
            Parts   = $null
            Child   = $null
            KeyText = ''
        })

    while ($stack.Count -gt 0) {
        $frame = $stack.Peek()
        if ($frame.State -eq 'Start') {
            if ($frame.Node.ReferenceId -ne 0 -and
                $EmittedReferences.Contains($frame.Node.ReferenceId)) {
                $frame.Holder.Value = "*$($frame.Node.Anchor)"
                [void] $stack.Pop()
                continue
            }
            if ($frame.Node.ReferenceId -ne 0) {
                [void] $EmittedReferences.Add($frame.Node.ReferenceId)
            }
            $frame.Prefix = Get-YamlEmissionPrefix -Node $frame.Node
            if (-not [string]::IsNullOrEmpty($frame.Prefix)) {
                $frame.Prefix += ' '
            }

            if ($frame.Node.Kind -eq 'Scalar') {
                $text = if ($frame.Node.Style -eq 'Plain') {
                    $frame.Node.Value
                } else {
                    ConvertTo-YamlQuotedText -Value $frame.Node.Value
                }
                $frame.Holder.Value = $frame.Prefix + $text
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
                $frame.Holder.Value = $frame.Prefix + '[{0}]' -f (
                    $frame.Parts -join ', '
                )
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
                    Prefix  = ''
                    Parts   = $null
                    Child   = $null
                    KeyText = ''
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
                $frame.Holder.Value = $frame.Prefix + '{{{0}}}' -f (
                    $frame.Parts -join ', '
                )
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
                    Prefix  = ''
                    Parts   = $null
                    Child   = $null
                    KeyText = ''
                })
            continue
        }
        if ($frame.State -eq 'MappingKeyValue') {
            $frame.KeyText = $frame.Child.Value
            $frame.Child = [pscustomobject]@{ Value = '' }
            $frame.State = 'MappingValue'
            $stack.Push([pscustomobject]@{
                    Node    = $frame.Node.Entries[$frame.Index].Value
                    Holder  = $frame.Child
                    State   = 'Start'
                    Index   = 0
                    Prefix  = ''
                    Parts   = $null
                    Child   = $null
                    KeyText = ''
                })
            continue
        }
        if ($frame.State -eq 'MappingValue') {
            $frame.Parts.Add("$($frame.KeyText)`: $($frame.Child.Value)")
            $frame.Index++
            $frame.State = 'MappingKey'
        }
    }

    $root.Value
}
