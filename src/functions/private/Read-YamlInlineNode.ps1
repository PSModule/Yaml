function Read-YamlInlineNode {
    <#
        .SYNOPSIS
        Reads a quoted, alias, or flow node beginning on the current block line.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [int] $Column,

        [Parameter(Mandatory)]
        [int] $ParentIndent,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth,

        [AllowEmptyString()]
        [string] $Tag = '',

        [bool] $HasUnknownTag = $false,

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
