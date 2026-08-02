function Read-YamlPlainScalar {
    <#
        .SYNOPSIS
        Reads a block-context plain scalar and its folded continuation lines.

        .DESCRIPTION
        Validates the first plain-scalar segment, folds eligible continuation
        lines, and rejects block mapping indicators that would end the scalar.
        The block parser uses it to produce scalar nodes from unquoted content.

        .EXAMPLE
        Read-YamlPlainScalar -Context $context -FirstText 'name value' -FirstColumn 2 -ParentIndent 0 -Depth 2

        Returns a plain scalar node with the folded value from the current block.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # Parser state containing source lines, cursor position, and limits.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # First source segment that starts the plain scalar value.
        [Parameter(Mandatory)]
        [string] $FirstText,

        # Source column used to create marks for diagnostics and the node span.
        [Parameter(Mandatory)]
        [int] $FirstColumn,

        # Indentation of the containing block that bounds scalar continuation.
        [Parameter(Mandatory)]
        [int] $ParentIndent,

        # Node depth assigned to the scalar for depth-limit enforcement.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth,

        # Explicit tag already parsed for this scalar, when one was supplied.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Tag = '',

        # Preserves whether the parsed tag was unknown to schema construction.
        [Parameter()]
        [bool] $HasUnknownTag = $false,

        # Anchor name to register on the scalar node, when one was supplied.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Anchor = ''
    )

    $startLine = $Context.LineIndex
    $start = New-YamlMark -Index ($Context.LineStarts[$startLine] + $FirstColumn) -Line $startLine `
        -Column $FirstColumn
    $parts = [System.Collections.Generic.List[object]]::new()
    $firstComment = Find-YamlCommentStart -Text $FirstText
    $firstValue = Get-YamlContentWithoutComment -Text $FirstText -Mark $start
    $firstValue = $firstValue.Trim(' ', "`t")
    Assert-YamlNoByteOrderMark -Text $firstValue -Mark $start
    $firstCharacter = if ($firstValue.Length -gt 0) { $firstValue[0] } else { [char] 0 }
    $forbiddenFirst = $firstCharacter -in @(
        ',', '[', ']', '{', '}', '#', '&', '*', '!', '|', '>', "'", '"', '%', '@', '`'
    )
    $conditionalIndicator = $firstCharacter -in @('-', '?', ':')
    if ($forbiddenFirst -or (
            $conditionalIndicator -and (
                $firstValue.Length -eq 1 -or (Test-YamlWhiteSpace -Character $firstValue[1])
            )
        )) {
        throw (New-YamlException -Start $start -End $start -ErrorId 'YamlInvalidPlainScalar' -Message (
                'The first character is not allowed in a YAML plain scalar.'
            ))
    }
    if ((Find-YamlMappingColon -Text $firstValue) -ge 0) {
        throw (New-YamlException -Start $start -End $start -ErrorId 'YamlInvalidPlainScalar' -Message (
                'A mapping value indicator cannot occur in a block plain scalar.'
            ))
    }
    if ($firstValue.Length -gt $Context.MaxScalarLength) {
        throw (New-YamlException -Start $start -End $start -ErrorId 'YamlScalarLimitExceeded' -Message (
                "A YAML scalar exceeds the configured limit of $($Context.MaxScalarLength) characters."
            ))
    }
    $parts.Add($firstValue)
    $decodedLength = $firstValue.Length
    $Context.LineIndex++
    $pendingBreaks = 0

    while ($firstComment -lt 0 -and $Context.LineIndex -lt $Context.Lines.Count) {
        $line = $Context.Lines[$Context.LineIndex]
        $trimmed = $line.TrimStart(' ', "`t")
        if ($line -match '^(?:---|\.\.\.)(?:[ \t]|$)' -or
            (Test-YamlDocumentByteOrderMark -Context $Context -RequireDocumentStart)) {
            break
        }
        if ($trimmed.Length -eq 0) {
            $pendingBreaks++
            $Context.LineIndex++
            continue
        }
        if ($trimmed.StartsWith('#', [System.StringComparison]::Ordinal)) {
            break
        }
        $indent = Get-YamlIndent -Line $line -LineNumber $Context.LineIndex -Context $Context
        if ($indent -le $ParentIndent) {
            break
        }
        $sourceContent = $line.Substring($indent)
        $comment = Find-YamlCommentStart -Text $sourceContent
        $contentMark = New-YamlMark -Index ($Context.LineStarts[$Context.LineIndex] + $indent) `
            -Line $Context.LineIndex -Column $indent
        $content = Get-YamlContentWithoutComment -Text $sourceContent -Mark $contentMark
        if ((Find-YamlMappingColon -Text $content) -ge 0) {
            break
        }
        $trimmedContent = $content.Trim(' ', "`t")
        Assert-YamlNoByteOrderMark -Text $trimmedContent -Mark $start
        $separatorLength = if ($pendingBreaks -gt 0) { $pendingBreaks } else { 1 }
        if ($decodedLength + $separatorLength + $trimmedContent.Length -gt
            $Context.MaxScalarLength) {
            throw (New-YamlException -Start $start -End $start -ErrorId 'YamlScalarLimitExceeded' -Message (
                    "A YAML scalar exceeds the configured limit of $($Context.MaxScalarLength) characters."
                ))
        }
        if ($pendingBreaks -gt 0) {
            $parts.Add("`n" * $pendingBreaks)
            $decodedLength += $pendingBreaks
            $pendingBreaks = 0
        } else {
            $parts.Add(' ')
            $decodedLength++
        }
        $parts.Add($trimmedContent)
        $decodedLength += $trimmedContent.Length
        $Context.LineIndex++
        if ($comment -ge 0) {
            break
        }
    }

    $value = -join $parts
    $endLine = [Math]::Max($startLine, $Context.LineIndex - 1)
    $end = New-YamlMark -Index ($Context.LineStarts[$endLine] + $Context.Lines[$endLine].Length) `
        -Line $endLine -Column $Context.Lines[$endLine].Length
    $node = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth $Depth -Start $start -End $end
    Set-YamlParsedNodeProperty -Node $node -Tag $Tag -HasUnknownTag $HasUnknownTag -Anchor $Anchor `
        -Context $Context
    $node.Value = $value
    $node.Style = 'Plain'
    $node.IsPlainImplicit = [string]::IsNullOrEmpty($Tag) -and -not $HasUnknownTag
    return $node
}
