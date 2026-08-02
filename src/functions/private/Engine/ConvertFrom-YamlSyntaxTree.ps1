function ConvertFrom-YamlSyntaxTree {
    <#
        .SYNOPSIS
        Iteratively composes syntax tokens into a representation graph.

        .DESCRIPTION
        Builds the internal YAML node graph from parser syntax tokens while
        preserving node identity, anchors, tags, scalar metadata, and aliases.
        The iterative cache-based walk avoids recursion and keeps shared nodes
        shared for the constructor pipeline.

        .EXAMPLE
        ConvertFrom-YamlSyntaxTree -Root $syntaxTree

        Returns the composed representation graph rooted at the parsed syntax tree.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The parsed syntax root to compose into reusable representation nodes.
        [Parameter(Mandatory)]
        [pscustomobject] $Root
    )

    $result = [pscustomobject]@{ Value = $null }
    $cache = [System.Collections.Generic.Dictionary[int, object]]::new()
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{
            Source = $Root
            Holder = $result
            Target = $null
            Child  = $null
            State  = 'Start'
            Index  = 0
            Key    = $null
        })

    while ($stack.Count -gt 0) {
        $frame = $stack.Peek()
        if ($frame.State -eq 'Start') {
            if ($cache.ContainsKey($frame.Source.Id)) {
                $frame.Holder.Value = $cache[$frame.Source.Id]
                [void] $stack.Pop()
                continue
            }

            $target = New-YamlNode -Id $frame.Source.Id -Kind $frame.Source.Kind `
                -Start $frame.Source.Start -End $frame.Source.End
            $target.Tag = $frame.Source.Tag
            $target.HasUnknownTag = $frame.Source.HasUnknownTag
            $target.Anchor = $frame.Source.Anchor
            $target.Value = $frame.Source.Value
            $target.Style = $frame.Source.Style
            $target.IsPlainImplicit = $frame.Source.IsPlainImplicit
            $target.IsQuotedImplicit = $frame.Source.IsQuotedImplicit
            $target.MaxNumericLength = $frame.Source.MaxNumericLength
            $cache[$frame.Source.Id] = $target
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
                        State  = 'Start'
                        Index  = 0
                        Key    = $null
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
                    State  = 'Start'
                    Index  = 0
                    Key    = $null
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
                    State  = 'Start'
                    Index  = 0
                    Key    = $null
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
                    State  = 'Start'
                    Index  = 0
                    Key    = $null
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

    $result.Value
}
