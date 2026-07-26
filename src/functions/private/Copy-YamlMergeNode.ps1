function Copy-YamlMergeNode {
    <#
        .SYNOPSIS
        Deep-clones a YAML representation graph with identity memoization.

        .DESCRIPTION
        Deep-clones a representation node and descendants into the merge working
        graph so overlays never mutate caller-owned input graphs. Identity
        memoization preserves shared and cyclic references while enforcing clone
        creation budgets.

        .EXAMPLE
        Copy-YamlMergeNode -Node $overlayNode -Cache $mergeContext.CloneCache -State $mergeContext.CloneState

        Returns an independent clone of the overlay node registered in the merge
        clone cache.

        .LINK
        https://psmodule.io/Yaml/Functions/Merge-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an isolated in-memory representation graph.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The representation graph root to clone into merge-owned storage.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # Memoizes source-to-clone identity so aliases, sharing, and cycles are preserved.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[int, object]] $Cache,

        # Tracks clone IDs and creation limits for the isolated working graph.
        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    if ($Cache.ContainsKey($Node.Id)) {
        Write-Output -InputObject $Cache[$Node.Id] -NoEnumerate
        return
    }

    $result = [pscustomobject]@{ Value = $null }
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{
            Source = $Node
            Holder = $result
            Target = $null
            Child  = $null
            Key    = $null
            Index  = 0
            State  = 'Start'
        })

    while ($stack.Count -gt 0) {
        $frame = $stack.Peek()
        if ($frame.State -eq 'Start') {
            if ($Cache.ContainsKey($frame.Source.Id)) {
                $frame.Holder.Value = $Cache[$frame.Source.Id]
                [void] $stack.Pop()
                continue
            }

            $State.CreatedNodes++
            if ($State.CreatedNodes -gt $State.MaxNodes) {
                throw (New-YamlMergeException -Node $frame.Source `
                        -ErrorId 'YamlMergeNodeLimitExceeded' -Message (
                        "Cloning the merged YAML graph exceeded the configured limit of $($State.MaxNodes) nodes."
                    ))
            }
            $target = New-YamlNode -Id $State.NextId -Kind $frame.Source.Kind `
                -Start $frame.Source.Start -End $frame.Source.End
            $State.NextId++
            $target.Tag = [string] $frame.Source.Tag
            $target.HasUnknownTag = [bool] $frame.Source.HasUnknownTag
            $target.Anchor = [string] $frame.Source.Anchor
            $target.Value = $frame.Source.Value
            $target.Style = [string] $frame.Source.Style
            $target.IsPlainImplicit = [bool] $frame.Source.IsPlainImplicit
            $target.IsQuotedImplicit = [bool] $frame.Source.IsQuotedImplicit
            $target.MaxNumericLength = [int] $frame.Source.MaxNumericLength
            $Cache[$frame.Source.Id] = $target
            $frame.Target = $target
            $frame.Holder.Value = $target

            if ($frame.Source.Kind -eq 'Scalar') {
                [void] $stack.Pop()
            } elseif ($frame.Source.Kind -eq 'Alias') {
                $frame.Child = [pscustomobject]@{ Value = $null }
                $frame.State = 'Alias'
                $stack.Push([pscustomobject]@{
                        Source = $frame.Source.Target
                        Holder = $frame.Child
                        Target = $null
                        Child  = $null
                        Key    = $null
                        Index  = 0
                        State  = 'Start'
                    })
            } elseif ($frame.Source.Kind -eq 'Sequence') {
                $frame.State = 'Sequence'
            } else {
                $frame.State = 'MappingKey'
            }
            continue
        }

        if ($frame.State -eq 'Alias') {
            $frame.Target.Target = $frame.Child.Value
            [void] $stack.Pop()
            continue
        }
        if ($frame.State -eq 'Sequence') {
            if ($frame.Index -ge $frame.Source.Items.Count) {
                [void] $stack.Pop()
                continue
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'SequenceValue'
            $stack.Push([pscustomobject]@{
                    Source = $frame.Source.Items[$frame.Index]
                    Holder = $frame.Child
                    Target = $null
                    Child  = $null
                    Key    = $null
                    Index  = 0
                    State  = 'Start'
                })
            continue
        }
        if ($frame.State -eq 'SequenceValue') {
            $frame.Target.Items.Add($frame.Child.Value)
            $frame.Index++
            $frame.State = 'Sequence'
            continue
        }
        if ($frame.State -eq 'MappingKey') {
            if ($frame.Index -ge $frame.Source.Entries.Count) {
                [void] $stack.Pop()
                continue
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'MappingKeyValue'
            $stack.Push([pscustomobject]@{
                    Source = $frame.Source.Entries[$frame.Index].Key
                    Holder = $frame.Child
                    Target = $null
                    Child  = $null
                    Key    = $null
                    Index  = 0
                    State  = 'Start'
                })
            continue
        }
        if ($frame.State -eq 'MappingKeyValue') {
            $frame.Key = $frame.Child.Value
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'MappingValue'
            $stack.Push([pscustomobject]@{
                    Source = $frame.Source.Entries[$frame.Index].Value
                    Holder = $frame.Child
                    Target = $null
                    Child  = $null
                    Key    = $null
                    Index  = 0
                    State  = 'Start'
                })
            continue
        }
        if ($frame.State -eq 'MappingValue') {
            $frame.Target.Entries.Add([pscustomobject]@{
                    Key   = $frame.Key
                    Value = $frame.Child.Value
                })
            $frame.Index++
            $frame.State = 'MappingKey'
        }
    }

    Write-Output -InputObject $result.Value -NoEnumerate
}
