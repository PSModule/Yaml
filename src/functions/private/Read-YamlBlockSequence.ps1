function Read-YamlBlockSequence {
    <#
        .SYNOPSIS
        Reads a block sequence, including compact first items.

        .DESCRIPTION
        Reads sequence entries at a fixed block indentation, including an item
        already split from a parent line. It creates empty items when needed and
        delegates nested content back into the block node reader.

        .EXAMPLE
        Read-YamlBlockSequence -Context $context -Indent 0 -Depth 1 -FirstItemText 'name: api' -FirstItemColumn 2

        Returns a sequence syntax node with the compact first item parsed.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # Parser state positioned at the sequence or its compact first item.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # Required indentation column for sequence indicators in this block.
        [Parameter(Mandatory)]
        [int] $Indent,

        # Node depth assigned to the sequence for parser limit accounting.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth,

        # Explicit tag to attach to the sequence, when one was parsed.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Tag = '',

        # Preserves whether the sequence tag is unknown to the schema.
        [Parameter()]
        [bool] $HasUnknownTag = $false,

        # Anchor name to register on the sequence node, when supplied.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Anchor = '',

        # Compact first item text already separated from its dash indicator.
        [Parameter()]
        [AllowNull()]
        [string] $FirstItemText,

        # Source column of the compact first item for marks and diagnostics.
        [Parameter()]
        [int] $FirstItemColumn = -1
    )

    $startLine = $Context.LineIndex
    $startColumn = if ($FirstItemColumn -ge 0) { $FirstItemColumn - 2 } else { $Indent }
    $start = New-YamlMark -Index ($Context.LineStarts[$startLine] + [Math]::Max(0, $startColumn)) `
        -Line $startLine -Column ([Math]::Max(0, $startColumn))
    $node = New-YamlSyntaxNode -Context $Context -Kind Sequence -Depth $Depth -Start $start -End $start
    Set-YamlParsedNodeProperty -Node $node -Tag $Tag -HasUnknownTag $HasUnknownTag -Anchor $Anchor `
        -Context $Context

    $hasFirstItem = $PSBoundParameters.ContainsKey('FirstItemText')
    while ($hasFirstItem -or $Context.LineIndex -lt $Context.Lines.Count) {
        if ($hasFirstItem) {
            $rest = $FirstItemText
            $itemColumn = $FirstItemColumn
            $hasFirstItem = $false
        } else {
            $line = $Context.Lines[$Context.LineIndex]
            $trimmed = $line.TrimStart(' ', "`t")
            if ($line -match '^(?:---|\.\.\.)(?:[ \t]|$)' -or
                (Test-YamlDocumentByteOrderMark -Context $Context -RequireDocumentStart)) {
                break
            }
            if ($trimmed.StartsWith('#', [System.StringComparison]::Ordinal)) {
                $column = $line.Length - $trimmed.Length
                $mark = New-YamlMark -Index ($Context.LineStarts[$Context.LineIndex] + $column) `
                    -Line $Context.LineIndex -Column $column
                Assert-YamlNoByteOrderMark -Text $trimmed -Mark $mark
                $Context.LineIndex++
                continue
            }
            if ($trimmed.Length -eq 0) {
                $Context.LineIndex++
                continue
            }
            $lineIndent = Get-YamlIndent -Line $line -LineNumber $Context.LineIndex -Context $Context
            if ($lineIndent -ne $Indent) {
                break
            }
            $content = $line.Substring($Indent)
            if (-not (Test-YamlIndicator -Text $content -Indicator '-')) {
                break
            }
            $rest = $content.Substring(1).TrimStart(' ', "`t")
            $itemColumn = $Indent + 1 + (
                $content.Substring(1).Length -
                $content.Substring(1).TrimStart(' ', "`t").Length
            )
        }

        $restMark = New-YamlMark -Index (
            $Context.LineStarts[$Context.LineIndex] + $itemColumn
        ) -Line $Context.LineIndex -Column $itemColumn
        if ([string]::IsNullOrEmpty((
                    Get-YamlContentWithoutComment -Text $rest -Mark $restMark
                ))) {
            $line = $Context.LineIndex
            $Context.LineIndex++
            Skip-YamlBlockTrivia -Context $Context
            if ($Context.LineIndex -ge $Context.Lines.Count) {
                $mark = New-YamlMark -Index ($Context.LineStarts[$line] + $itemColumn) -Line $line `
                    -Column $itemColumn
                $item = New-YamlEmptyScalar -Context $Context -Depth ($Depth + 1) -Mark $mark
            } else {
                $nextLine = $Context.Lines[$Context.LineIndex]
                $nextIndent = Get-YamlIndent -Line $nextLine -LineNumber $Context.LineIndex -Context $Context
                if ($nextIndent -le $Indent -or
                    $nextLine -match '^(?:---|\.\.\.)(?:[ \t]|$)' -or
                    (Test-YamlDocumentByteOrderMark -Context $Context -RequireDocumentStart)) {
                    $mark = New-YamlMark -Index ($Context.LineStarts[$line] + $itemColumn) -Line $line `
                        -Column $itemColumn
                    $item = New-YamlEmptyScalar -Context $Context -Depth ($Depth + 1) -Mark $mark
                } else {
                    $item = Read-YamlBlockNode -Context $Context -ParentIndent $Indent -Depth ($Depth + 1)
                }
            }
        } else {
            $item = Read-YamlBlockNode -Context $Context -ParentIndent $Indent -Depth ($Depth + 1) `
                -Segment $rest -SegmentColumn $itemColumn
        }
        $node.Items.Add($item)
    }

    $endLine = [Math]::Max($startLine, $Context.LineIndex - 1)
    $node.End = New-YamlMark -Index ($Context.LineStarts[$endLine] + $Context.Lines[$endLine].Length) `
        -Line $endLine -Column $Context.Lines[$endLine].Length
    return $node
}
