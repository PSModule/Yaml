function Read-YamlNode {
    <#
        .SYNOPSIS
        Reads one representation node from the low-level YAML event stream.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [YamlDotNet.Core.Parser] $Parser,

        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1024)]
        [int] $Depth
    )

    $parserEvent = $Parser.Current
    if ($null -eq $parserEvent) {
        throw (New-YamlException -Start ([YamlDotNet.Core.Mark]::Empty) -End ([YamlDotNet.Core.Mark]::Empty) -ErrorId 'YamlUnexpectedEnd' -Message (
                'The YAML stream ended while a node was expected.'
            ))
    }
    if ($Depth -gt $Context.MaxDepth) {
        throw (New-YamlException -Start $parserEvent.Start -End $parserEvent.End -ErrorId 'YamlDepthExceeded' -Message (
                "The YAML nesting depth exceeds the configured limit of $($Context.MaxDepth)."
            ))
    }

    $Context.NodeCount++
    if ($Context.NodeCount -gt $Context.MaxNodes) {
        throw (New-YamlException -Start $parserEvent.Start -End $parserEvent.End -ErrorId 'YamlNodeLimitExceeded' -Message (
                "The YAML stream exceeds the configured limit of $($Context.MaxNodes) nodes."
            ))
    }

    $id = $Context.NextId
    $Context.NextId++

    if ($parserEvent -is [YamlDotNet.Core.Events.AnchorAlias]) {
        $Context.AliasCount++
        if ($Context.AliasCount -gt $Context.MaxAliases) {
            throw (New-YamlException -Start $parserEvent.Start -End $parserEvent.End -ErrorId 'YamlAliasLimitExceeded' -Message (
                    "The YAML stream exceeds the configured limit of $($Context.MaxAliases) aliases."
                ))
        }
        $anchorName = $parserEvent.Value.Value
        if (-not $Context.Anchors.ContainsKey($anchorName)) {
            throw (New-YamlException -Start $parserEvent.Start -End $parserEvent.End -ErrorId 'YamlUndefinedAlias' -Message (
                    "The YAML alias '*$anchorName' does not refer to a preceding anchor."
                ))
        }
        $node = New-YamlNode -Id $id -Kind Alias -Start $parserEvent.Start -End $parserEvent.End
        $node.Target = $Context.Anchors[$anchorName]
        [void] $Parser.MoveNext()
        Write-Output -InputObject $node -NoEnumerate
        return
    }

    if ($parserEvent -is [YamlDotNet.Core.Events.Scalar]) {
        if ($parserEvent.Value.Length -gt $Context.MaxScalarLength) {
            throw (New-YamlException -Start $parserEvent.Start -End $parserEvent.End -ErrorId 'YamlScalarLimitExceeded' -Message (
                    "A YAML scalar exceeds the configured limit of $($Context.MaxScalarLength) characters."
                ))
        }
        $node = New-YamlNode -Id $id -Kind Scalar -Start $parserEvent.Start -End $parserEvent.End
        $node.Tag = $parserEvent.Tag.Value
        $node.Anchor = $parserEvent.Anchor.Value
        $node.Value = $parserEvent.Value
        $node.Style = $parserEvent.Style
        $node.IsPlainImplicit = $parserEvent.IsPlainImplicit
        $node.IsQuotedImplicit = $parserEvent.IsQuotedImplicit
        if (-not [string]::IsNullOrEmpty($node.Anchor)) {
            $Context.Anchors[$node.Anchor] = $node
        }
        [void] $Parser.MoveNext()
        Write-Output -InputObject $node -NoEnumerate
        return
    }

    if ($parserEvent -is [YamlDotNet.Core.Events.SequenceStart]) {
        $node = New-YamlNode -Id $id -Kind Sequence -Start $parserEvent.Start -End $parserEvent.End
        $node.Tag = $parserEvent.Tag.Value
        $node.Anchor = $parserEvent.Anchor.Value
        if (-not [string]::IsNullOrEmpty($node.Anchor)) {
            $Context.Anchors[$node.Anchor] = $node
        }
        if (-not $Parser.MoveNext()) {
            throw (New-YamlException -Start $parserEvent.Start -End $parserEvent.End -ErrorId 'YamlUnexpectedEnd' -Message (
                    'The YAML stream ended inside a sequence.'
                ))
        }
        while ($Parser.Current -isnot [YamlDotNet.Core.Events.SequenceEnd]) {
            $item = Read-YamlNode -Parser $Parser -Context $Context -Depth ($Depth + 1)
            $node.Items.Add($item)
            if ($null -eq $Parser.Current) {
                throw (New-YamlException -Start $parserEvent.Start -End $parserEvent.End -ErrorId 'YamlUnexpectedEnd' -Message (
                        'The YAML stream ended inside a sequence.'
                    ))
            }
        }
        $node.End = $Parser.Current.End
        [void] $Parser.MoveNext()
        Write-Output -InputObject $node -NoEnumerate
        return
    }

    if ($parserEvent -is [YamlDotNet.Core.Events.MappingStart]) {
        $node = New-YamlNode -Id $id -Kind Mapping -Start $parserEvent.Start -End $parserEvent.End
        $node.Tag = $parserEvent.Tag.Value
        $node.Anchor = $parserEvent.Anchor.Value
        if (-not [string]::IsNullOrEmpty($node.Anchor)) {
            $Context.Anchors[$node.Anchor] = $node
        }
        if (-not $Parser.MoveNext()) {
            throw (New-YamlException -Start $parserEvent.Start -End $parserEvent.End -ErrorId 'YamlUnexpectedEnd' -Message (
                    'The YAML stream ended inside a mapping.'
                ))
        }
        while ($Parser.Current -isnot [YamlDotNet.Core.Events.MappingEnd]) {
            $key = Read-YamlNode -Parser $Parser -Context $Context -Depth ($Depth + 1)
            $entryValue = Read-YamlNode -Parser $Parser -Context $Context -Depth ($Depth + 1)
            $node.Entries.Add([pscustomobject]@{
                    Key   = $key
                    Value = $entryValue
                })
            if ($null -eq $Parser.Current) {
                throw (New-YamlException -Start $parserEvent.Start -End $parserEvent.End -ErrorId 'YamlUnexpectedEnd' -Message (
                        'The YAML stream ended inside a mapping.'
                    ))
            }
        }
        $node.End = $Parser.Current.End
        [void] $Parser.MoveNext()
        Write-Output -InputObject $node -NoEnumerate
        return
    }

    throw (New-YamlException -Start $parserEvent.Start -End $parserEvent.End -ErrorId 'YamlUnexpectedEvent' -Message (
            "Unexpected YAML parser event '$($parserEvent.GetType().Name)'."
        ))
}
