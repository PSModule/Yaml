function Read-YamlBlockNode {
    <#
        .SYNOPSIS
        Reads one node in block context.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [int] $ParentIndent,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth,

        [AllowNull()]
        [string] $Segment,

        [int] $SegmentColumn = -1,

        [AllowEmptyString()]
        [string] $PendingTag = '',

        [bool] $PendingUnknownTag = $false,

        [AllowEmptyString()]
        [string] $PendingAnchor = '',

        [switch] $AllowIndentlessSequence
    )

    $hasSegment = $PSBoundParameters.ContainsKey('Segment')
    if (-not $hasSegment) {
        Skip-YamlBlockTrivia -Context $Context
        if ($Context.LineIndex -ge $Context.Lines.Count) {
            $mark = New-YamlMark -Index $Context.Text.Length -Line ([Math]::Max(0, $Context.Lines.Count - 1)) `
                -Column 0
            return New-YamlEmptyScalar -Context $Context -Depth $Depth -Mark $mark -Tag $PendingTag `
                -HasUnknownTag $PendingUnknownTag -Anchor $PendingAnchor
        }
        $line = $Context.Lines[$Context.LineIndex]
        if ($line -match '^(?:---|\.\.\.)(?:[ \t]|$)') {
            $mark = New-YamlMark -Index $Context.LineStarts[$Context.LineIndex] -Line $Context.LineIndex -Column 0
            return New-YamlEmptyScalar -Context $Context -Depth $Depth -Mark $mark -Tag $PendingTag `
                -HasUnknownTag $PendingUnknownTag -Anchor $PendingAnchor
        }
        $indent = Get-YamlIndent -Line $line -LineNumber $Context.LineIndex -Context $Context
        if ($indent -le $ParentIndent -and -not (
                $indent -eq $ParentIndent -and
                (Test-YamlIndicator -Text $line.Substring($indent) -Indicator '-')
            )) {
            $mark = New-YamlMark -Index ($Context.LineStarts[$Context.LineIndex] + $indent) `
                -Line $Context.LineIndex -Column $indent
            return New-YamlEmptyScalar -Context $Context -Depth $Depth -Mark $mark -Tag $PendingTag `
                -HasUnknownTag $PendingUnknownTag -Anchor $PendingAnchor
        }
        $Segment = $line.Substring($indent)
        $SegmentColumn = $indent
    } else {
        $indent = $ParentIndent + 1
    }

    $lineNumber = $Context.LineIndex
    if (
        (-not [string]::IsNullOrEmpty($PendingTag) -or $PendingUnknownTag -or
        -not [string]::IsNullOrEmpty($PendingAnchor)) -and
        -not (Test-YamlIndicator -Text $Segment -Indicator '-') -and
        ((Find-YamlMappingColon -Text $Segment) -ge 0 -or
        (Test-YamlIndicator -Text $Segment -Indicator '?'))
    ) {
        return Read-YamlBlockMapping -Context $Context -Indent $SegmentColumn -Depth $Depth `
            -Tag $PendingTag -HasUnknownTag $PendingUnknownTag -Anchor $PendingAnchor `
            -FirstText $Segment -FirstColumn $SegmentColumn
    }
    if (
        [string]::IsNullOrEmpty($PendingTag) -and -not $PendingUnknownTag -and
        [string]::IsNullOrEmpty($PendingAnchor) -and
        -not (Test-YamlIndicator -Text $Segment -Indicator '-') -and
        ((Find-YamlMappingColon -Text $Segment) -ge 0 -or
        (Test-YamlIndicator -Text $Segment -Indicator '?'))
    ) {
        return Read-YamlBlockMapping -Context $Context -Indent $SegmentColumn -Depth $Depth `
            -FirstText $Segment -FirstColumn $SegmentColumn
    }

    $properties = Read-YamlNodeProperty -Text $Segment -Line $lineNumber -Column $SegmentColumn `
        -Context $Context
    if ((-not [string]::IsNullOrEmpty($PendingTag) -or $PendingUnknownTag) -and
        (-not [string]::IsNullOrEmpty($properties.Tag) -or $properties.HasUnknownTag)) {
        $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $SegmentColumn) -Line $lineNumber `
            -Column $SegmentColumn
        throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlDuplicateNodeProperty' -Message (
                'A YAML node cannot have more than one tag property.'
            ))
    }
    if (-not [string]::IsNullOrEmpty($PendingAnchor) -and
        -not [string]::IsNullOrEmpty($properties.Anchor)) {
        $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $SegmentColumn) -Line $lineNumber `
            -Column $SegmentColumn
        throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlDuplicateNodeProperty' -Message (
                'A YAML node cannot have more than one anchor property.'
            ))
    }
    $tag = if (-not [string]::IsNullOrEmpty($properties.Tag)) { $properties.Tag } else { $PendingTag }
    $unknownTag = $properties.HasUnknownTag -or $PendingUnknownTag
    $anchor = if (-not [string]::IsNullOrEmpty($properties.Anchor)) { $properties.Anchor } else { $PendingAnchor }
    $restSource = $properties.Rest
    $rest = Get-YamlContentWithoutComment -Text $restSource
    $contentColumn = $SegmentColumn + $properties.Consumed

    if ([string]::IsNullOrWhiteSpace($rest)) {
        $Context.LineIndex++
        Skip-YamlBlockTrivia -Context $Context
        if ($Context.LineIndex -ge $Context.Lines.Count -or
            $Context.Lines[$Context.LineIndex] -match '^(?:---|\.\.\.)(?:[ \t]|$)') {
            $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $contentColumn) `
                -Line $lineNumber -Column $contentColumn
            return New-YamlEmptyScalar -Context $Context -Depth $Depth -Mark $mark -Tag $tag `
                -HasUnknownTag $unknownTag -Anchor $anchor
        }
        $nextLine = $Context.Lines[$Context.LineIndex]
        $nextIndent = Get-YamlIndent -Line $nextLine -LineNumber $Context.LineIndex -Context $Context
        if ($AllowIndentlessSequence -and $nextIndent -eq $ParentIndent -and
            (Test-YamlIndicator -Text $nextLine.Substring($nextIndent) -Indicator '-')) {
            return Read-YamlBlockSequence -Context $Context -Indent $ParentIndent -Depth $Depth `
                -Tag $tag -HasUnknownTag $unknownTag -Anchor $anchor
        }
        if ($nextIndent -le $ParentIndent) {
            $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $contentColumn) `
                -Line $lineNumber -Column $contentColumn
            return New-YamlEmptyScalar -Context $Context -Depth $Depth -Mark $mark -Tag $tag `
                -HasUnknownTag $unknownTag -Anchor $anchor
        }
        return Read-YamlBlockNode -Context $Context -ParentIndent $ParentIndent -Depth $Depth `
            -PendingTag $tag -PendingUnknownTag $unknownTag -PendingAnchor $anchor `
            -AllowIndentlessSequence:$AllowIndentlessSequence
    }

    if ($rest[0] -in @('|', '>')) {
        return Read-YamlBlockScalar -Context $Context -Header $rest -HeaderColumn $contentColumn `
            -ParentIndent $ParentIndent -Depth $Depth -Tag $tag -HasUnknownTag $unknownTag -Anchor $anchor
    }

    if (Test-YamlIndicator -Text $rest -Indicator '-') {
        if ($properties.Consumed -gt 0) {
            $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $contentColumn) `
                -Line $lineNumber -Column $contentColumn
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidBlockSequence' -Message (
                    'Node properties cannot precede a block sequence entry on the same line.'
                ))
        }
        $firstSource = $rest.Substring(1)
        if ($firstSource.IndexOf("`t", [System.StringComparison]::Ordinal) -ge 0 -and
            $firstSource.Trim() -eq '-') {
            $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $contentColumn + 1) `
                -Line $lineNumber -Column ($contentColumn + 1)
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidIndentation' -Message (
                    'Tabs cannot separate adjacent block sequence indicators.'
                ))
        }
        $first = $firstSource
        $leading = $first.Length - $first.TrimStart().Length
        $first = $first.TrimStart()
        return Read-YamlBlockSequence -Context $Context -Indent $contentColumn -Depth $Depth -Tag $tag `
            -HasUnknownTag $unknownTag -Anchor $anchor -FirstItemText $first `
            -FirstItemColumn ($contentColumn + 1 + $leading)
    }

    if ((Find-YamlMappingColon -Text $rest) -ge 0 -or
        (Test-YamlIndicator -Text $rest -Indicator '?')) {
        return Read-YamlBlockMapping -Context $Context -Indent $contentColumn -Depth $Depth -Tag $tag `
            -HasUnknownTag $unknownTag -Anchor $anchor -FirstText $rest -FirstColumn $contentColumn
    }

    if ($rest[0] -in @('[', '{', "'", '"', '*')) {
        return Read-YamlInlineNode -Context $Context -Column $contentColumn -ParentIndent $ParentIndent `
            -Depth $Depth -Tag $tag -HasUnknownTag $unknownTag -Anchor $anchor
    }

    return Read-YamlPlainScalar -Context $Context -FirstText $restSource -FirstColumn $contentColumn `
        -ParentIndent $ParentIndent -Depth $Depth -Tag $tag -HasUnknownTag $unknownTag -Anchor $anchor
}
