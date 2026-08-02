function Read-YamlInlineNode {
    <#
        .SYNOPSIS
        Reads a quoted, alias, or flow node beginning on the current block line.

        .DESCRIPTION
        Creates a flow cursor at the current block line, delegates inline syntax
        to the flow reader, and verifies that only trivia follows on that line.
        This lets block parsing accept quoted scalars, aliases, and flow nodes.

        .EXAMPLE
        Read-YamlInlineNode -Context $context -Column 4 -ParentIndent 2 -Depth 3 -Anchor 'item'

        Reads the inline node and advances the block reader past its line.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # Parser state containing the current block line and source text.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # Source column where the inline node starts on the current line.
        [Parameter(Mandatory)]
        [int] $Column,

        # Surrounding block indent used to validate multiline inline scalars.
        [Parameter(Mandatory)]
        [int] $ParentIndent,

        # Node depth assigned to the inline node for depth-limit accounting.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth,

        # Explicit tag already parsed before the inline node, when present.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Tag = '',

        # Preserves whether the pending tag is unknown to the schema.
        [Parameter()]
        [bool] $HasUnknownTag = $false,

        # Anchor name already parsed before the inline node, when present.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Anchor = ''
    )

    $line = $Context.LineIndex
    $cursor = [pscustomobject]@{
        Index        = $Context.LineStarts[$line] + $Column
        Line         = $line
        Column       = $Column
        ParentIndent = $ParentIndent
    }
    $node = Read-YamlFlowNode -Cursor $cursor -Context $Context -Depth $Depth -PendingTag $Tag `
        -PendingUnknownTag $HasUnknownTag -PendingAnchor $Anchor

    $separated = $false
    while ($cursor.Index -lt $Context.Text.Length -and $Context.Text[$cursor.Index] -in @(' ', "`t")) {
        $separated = $true
        Move-YamlCursor -Cursor $cursor -Context $Context
    }
    if ($cursor.Index -lt $Context.Text.Length -and $Context.Text[$cursor.Index] -eq '#') {
        if (-not $separated) {
            $mark = New-YamlMark -Index $cursor.Index -Line $cursor.Line -Column $cursor.Column
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidComment' -Message (
                    'A YAML comment must be separated from preceding content.'
                ))
        }
        while ($cursor.Index -lt $Context.Text.Length -and $Context.Text[$cursor.Index] -ne "`n") {
            Move-YamlCursor -Cursor $cursor -Context $Context
        }
    }
    if ($cursor.Index -lt $Context.Text.Length -and $Context.Text[$cursor.Index] -ne "`n") {
        $mark = New-YamlMark -Index $cursor.Index -Line $cursor.Line -Column $cursor.Column
        throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlUnexpectedContent' -Message (
                'Unexpected content follows a YAML node.'
            ))
    }
    $Context.LineIndex = $cursor.Line + 1
    return $node
}
