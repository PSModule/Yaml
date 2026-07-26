function ConvertFrom-YamlNode {
    <#
        .SYNOPSIS
        Iteratively projects an internal YAML graph through a value box.

        .DESCRIPTION
        Converts composed YAML representation nodes into PowerShell values while
        resolving aliases and preserving shared collection identity through a
        cache. It selects PSCustomObject projection by default, or ordered
        dictionaries when requested or required by YAML collection tags.

        .EXAMPLE
        ConvertFrom-YamlNode -Node $document.Root -Cache ([System.Collections.Generic.Dictionary[int, object]]::new()) -AsHashtable

        Projects the document root into a value box containing ordered dictionaries.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The representation node whose aliases and children must be projected.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # The node-id cache that preserves alias identity and stops repeated work.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[int, object]] $Cache,

        # Requests dictionary projection so non-property YAML keys survive intact.
        [Parameter()]
        [switch] $AsHashtable
    )

    $root = [pscustomobject]@{ Value = $null }
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{
            Node        = $Node
            Holder      = $root
            AsHashtable = [bool] $AsHashtable
            State       = 'Start'
            Index       = 0
            Result      = $null
            Child       = $null
            Key         = $null
            Names       = $null
        })

    while ($stack.Count -gt 0) {
        $frame = $stack.Peek()
        if ($frame.State -eq 'Start') {
            $effective = $frame.Node
            while ($effective.Kind -eq 'Alias') {
                $effective = $effective.Target
            }
            $frame.Node = $effective

            if ($effective.Kind -eq 'Scalar') {
                $frame.Holder.PSObject.Properties['Value'].Value = (Resolve-YamlScalar -Node $effective).Value
                [void] $stack.Pop()
                continue
            }
            if ($Cache.ContainsKey($effective.Id)) {
                $frame.Holder.PSObject.Properties['Value'].Value = $Cache[$effective.Id]
                [void] $stack.Pop()
                continue
            }

            if ($effective.Kind -eq 'Sequence') {
                if ($effective.Tag -ceq 'tag:yaml.org,2002:omap') {
                    $frame.Result = [System.Collections.Specialized.OrderedDictionary]::new()
                    $frame.State = 'OmapKey'
                } else {
                    $frame.Result = [object[]]::new($effective.Items.Count)
                    $frame.State = 'Sequence'
                }
            } elseif ($frame.AsHashtable -or
                $effective.Tag -ceq 'tag:yaml.org,2002:set') {
                $frame.Result = [System.Collections.Specialized.OrderedDictionary]::new()
                $frame.State = 'DictionaryKey'
            } else {
                $frame.Result = [pscustomobject]@{}
                $frame.Names = [System.Collections.Generic.HashSet[string]]::new(
                    [System.StringComparer]::OrdinalIgnoreCase
                )
                $frame.State = 'PropertyKey'
            }
            $Cache[$effective.Id] = $frame.Result
            $frame.Holder.PSObject.Properties['Value'].Value = $frame.Result
            continue
        }

        if ($frame.State -eq 'Sequence') {
            if ($frame.Index -ge $frame.Node.Items.Count) {
                [void] $stack.Pop()
                continue
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'SequenceValue'
            $stack.Push([pscustomobject]@{
                    Node        = $frame.Node.Items[$frame.Index]
                    Holder      = $frame.Child
                    AsHashtable = $frame.AsHashtable -or
                    $frame.Node.Tag -ceq 'tag:yaml.org,2002:pairs'
                    State       = 'Start'
                    Index       = 0
                    Result      = $null
                    Child       = $null
                    Key         = $null
                    Names       = $null
                })
            continue
        }
        if ($frame.State -eq 'SequenceValue') {
            $frame.Result[$frame.Index] = $frame.Child.PSObject.Properties['Value'].Value
            $frame.Index++
            $frame.State = 'Sequence'
            continue
        }

        if ($frame.State -eq 'OmapKey') {
            if ($frame.Index -ge $frame.Node.Items.Count) {
                [void] $stack.Pop()
                continue
            }
            $entryNode = $frame.Node.Items[$frame.Index]
            while ($entryNode.Kind -eq 'Alias') {
                $entryNode = $entryNode.Target
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.Key = $entryNode
            $frame.State = 'OmapKeyValue'
            $stack.Push([pscustomobject]@{
                    Node        = $entryNode.Entries[0].Key
                    Holder      = $frame.Child
                    AsHashtable = $true
                    State       = 'Start'
                    Index       = 0
                    Result      = $null
                    Child       = $null
                    Key         = $null
                    Names       = $null
                })
            continue
        }
        if ($frame.State -eq 'OmapKeyValue') {
            $keyValue = $frame.Child.PSObject.Properties['Value'].Value
            if ([object]::ReferenceEquals($keyValue, $null)) {
                $frame.Key = [System.DBNull]::Value
            } else {
                $frame.Key = $keyValue
            }
            $entryNode = $frame.Node.Items[$frame.Index]
            while ($entryNode.Kind -eq 'Alias') {
                $entryNode = $entryNode.Target
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'OmapValue'
            $stack.Push([pscustomobject]@{
                    Node        = $entryNode.Entries[0].Value
                    Holder      = $frame.Child
                    AsHashtable = $true
                    State       = 'Start'
                    Index       = 0
                    Result      = $null
                    Child       = $null
                    Key         = $null
                    Names       = $null
                })
            continue
        }
        if ($frame.State -eq 'OmapValue') {
            Add-YamlDictionaryEntry -Dictionary $frame.Result -Key $frame.Key `
                -Value $frame.Child.PSObject.Properties['Value'].Value `
                -KeyNode $frame.Node.Items[$frame.Index].Entries[0].Key
            $frame.Index++
            $frame.State = 'OmapKey'
            continue
        }

        if ($frame.State -eq 'DictionaryKey') {
            if ($frame.Index -ge $frame.Node.Entries.Count) {
                [void] $stack.Pop()
                continue
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'DictionaryKeyValue'
            $stack.Push([pscustomobject]@{
                    Node        = $frame.Node.Entries[$frame.Index].Key
                    Holder      = $frame.Child
                    AsHashtable = $frame.AsHashtable
                    State       = 'Start'
                    Index       = 0
                    Result      = $null
                    Child       = $null
                    Key         = $null
                    Names       = $null
                })
            continue
        }
        if ($frame.State -eq 'DictionaryKeyValue') {
            $keyValue = $frame.Child.PSObject.Properties['Value'].Value
            if ([object]::ReferenceEquals($keyValue, $null)) {
                $frame.Key = [System.DBNull]::Value
            } else {
                $frame.Key = $keyValue
            }
            if ($frame.Node.Tag -ceq 'tag:yaml.org,2002:set') {
                Add-YamlDictionaryEntry -Dictionary $frame.Result -Key $frame.Key -Value $null `
                    -KeyNode $frame.Node.Entries[$frame.Index].Key
                $frame.Index++
                $frame.State = 'DictionaryKey'
                continue
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'DictionaryValue'
            $stack.Push([pscustomobject]@{
                    Node        = $frame.Node.Entries[$frame.Index].Value
                    Holder      = $frame.Child
                    AsHashtable = $frame.AsHashtable
                    State       = 'Start'
                    Index       = 0
                    Result      = $null
                    Child       = $null
                    Key         = $null
                    Names       = $null
                })
            continue
        }
        if ($frame.State -eq 'DictionaryValue') {
            Add-YamlDictionaryEntry -Dictionary $frame.Result -Key $frame.Key `
                -Value $frame.Child.PSObject.Properties['Value'].Value `
                -KeyNode $frame.Node.Entries[$frame.Index].Key
            $frame.Index++
            $frame.State = 'DictionaryKey'
            continue
        }

        if ($frame.State -eq 'PropertyKey') {
            if ($frame.Index -ge $frame.Node.Entries.Count) {
                [void] $stack.Pop()
                continue
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'PropertyKeyValue'
            $stack.Push([pscustomobject]@{
                    Node        = $frame.Node.Entries[$frame.Index].Key
                    Holder      = $frame.Child
                    AsHashtable = $false
                    State       = 'Start'
                    Index       = 0
                    Result      = $null
                    Child       = $null
                    Key         = $null
                    Names       = $null
                })
            continue
        }
        if ($frame.State -eq 'PropertyKeyValue') {
            $frame.Key = $frame.Child.PSObject.Properties['Value'].Value
            if ($frame.Key -isnot [string] -or [string]::IsNullOrEmpty($frame.Key)) {
                $keyNode = $frame.Node.Entries[$frame.Index].Key
                throw (New-YamlException -Start $keyNode.Start -End $keyNode.End `
                        -ErrorId 'YamlMappingKeyNotString' -Message (
                        'This mapping key cannot be represented as a PSCustomObject property. Use -AsHashtable.'
                    ))
            }
            if (Test-YamlReservedPropertyName -Name $frame.Key) {
                $keyNode = $frame.Node.Entries[$frame.Index].Key
                throw (New-YamlException -Start $keyNode.Start -End $keyNode.End `
                        -ErrorId 'YamlPropertyNameReserved' -Message (
                        "The mapping key '$($frame.Key)' is reserved by PowerShell ETS. Use -AsHashtable."
                    ))
            }
            if (-not $frame.Names.Add($frame.Key)) {
                $keyNode = $frame.Node.Entries[$frame.Index].Key
                throw (New-YamlException -Start $keyNode.Start -End $keyNode.End `
                        -ErrorId 'YamlPropertyNameCollision' -Message (
                        "The mapping keys contain a case-insensitive property collision for '$($frame.Key)'. Use -AsHashtable."
                    ))
            }
            $frame.Child = [pscustomobject]@{ Value = $null }
            $frame.State = 'PropertyValue'
            $stack.Push([pscustomobject]@{
                    Node        = $frame.Node.Entries[$frame.Index].Value
                    Holder      = $frame.Child
                    AsHashtable = $false
                    State       = 'Start'
                    Index       = 0
                    Result      = $null
                    Child       = $null
                    Key         = $null
                    Names       = $null
                })
            continue
        }
        if ($frame.State -eq 'PropertyValue') {
            $frame.Result.PSObject.Properties.Add(
                [System.Management.Automation.PSNoteProperty]::new(
                    [string] $frame.Key,
                    $frame.Child.PSObject.Properties['Value'].Value
                )
            )
            $frame.Index++
            $frame.State = 'PropertyKey'
        }
    }

    New-YamlValueBox -Value $root.PSObject.Properties['Value'].Value
}
