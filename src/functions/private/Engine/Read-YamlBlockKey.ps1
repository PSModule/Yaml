function Read-YamlBlockKey {
    <#
        .SYNOPSIS
        Reads one single-line implicit block mapping key.

        .DESCRIPTION
        Parses a single-line implicit mapping key, including node properties and
        flow or quoted key forms. Block mapping parsing uses it to validate key
        syntax and length before reading the associated value.

        .EXAMPLE
        Read-YamlBlockKey -Context $context -Text 'name' -Line 0 -Column 0 -Depth 2

        Returns a scalar key node for the implicit mapping entry.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # Parser context that supplies source offsets, limits, and tag handles.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # Key text sliced from the mapping entry before the value indicator.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        # Source line containing the implicit key for mark calculation.
        [Parameter(Mandatory)]
        [int] $Line,

        # Source column where the key text begins for diagnostics.
        [Parameter(Mandatory)]
        [int] $Column,

        # Node depth assigned to the key for nesting-limit accounting.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth
    )

    $properties = Read-YamlNodeProperty -Text $Text -Line $Line -Column $Column -Context $Context
    $rest = $properties.Rest
    $contentColumn = $Column + $properties.Consumed
    $start = New-YamlMark -Index ($Context.LineStarts[$Line] + $Column) -Line $Line -Column $Column

    if ([string]::IsNullOrEmpty($rest)) {
        $node = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth $Depth -Start $start -End $start
        Set-YamlParsedNodeProperty -Node $node -Tag $properties.Tag `
            -HasUnknownTag $properties.HasUnknownTag -Anchor $properties.Anchor -Context $Context
        $node.Value = ''
        $node.IsPlainImplicit = [string]::IsNullOrEmpty($properties.Tag) -and
        -not $properties.HasUnknownTag
        return $node
    }

    if ($rest[0] -in @('[', '{', "'", '"', '*')) {
        $cursor = [pscustomobject]@{
            Index        = $Context.LineStarts[$Line] + $contentColumn
            Line         = $Line
            Column       = $contentColumn
            ParentIndent = $Column
        }
        $node = Read-YamlFlowNode -Cursor $cursor -Context $Context -Depth $Depth `
            -PendingTag $properties.Tag -PendingUnknownTag $properties.HasUnknownTag `
            -PendingAnchor $properties.Anchor -InImplicitKey
        $expectedEnd = $Context.LineStarts[$Line] + $Column + $Text.Length
        while ($cursor.Index -lt $expectedEnd -and $Context.Text[$cursor.Index] -in @(' ', "`t")) {
            Move-YamlCursor -Cursor $cursor -Context $Context
        }
        if ($cursor.Index -ne $expectedEnd) {
            $mark = New-YamlMark -Index $cursor.Index -Line $cursor.Line -Column $cursor.Column
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidImplicitKey' -Message (
                    'An implicit block mapping key contains unexpected trailing content.'
                ))
        }
        return $node
    }

    Assert-YamlNoByteOrderMark -Text $rest -Mark $start
    $first = $rest[0]
    if ($first -in @(',', '[', ']', '{', '}', '#', '&', '*', '!', '|', '>', "'", '"', '%', '@', '`') -or
        ($first -in @('-', '?', ':') -and (
            $rest.Length -gt 1 -and (Test-YamlWhiteSpace -Character $rest[1])
        ))) {
        throw (New-YamlException -Start $start -End $start -ErrorId 'YamlInvalidPlainScalar' -Message (
                'The first character is not allowed in a YAML plain scalar.'
            ))
    }
    if ($rest.Length -gt $Context.MaxScalarLength) {
        throw (New-YamlException -Start $start -End $start -ErrorId 'YamlScalarLimitExceeded' -Message (
                "A YAML scalar exceeds the configured limit of $($Context.MaxScalarLength) characters."
            ))
    }

    $end = New-YamlMark -Index ($Context.LineStarts[$Line] + $Column + $Text.Length) `
        -Line $Line -Column ($Column + $Text.Length)
    $node = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth $Depth -Start $start -End $end
    Set-YamlParsedNodeProperty -Node $node -Tag $properties.Tag `
        -HasUnknownTag $properties.HasUnknownTag -Anchor $properties.Anchor -Context $Context
    $node.Value = $rest.TrimEnd(' ', "`t")
    $node.Style = 'Plain'
    $node.IsPlainImplicit = [string]::IsNullOrEmpty($properties.Tag) -and
    -not $properties.HasUnknownTag
    return $node
}
