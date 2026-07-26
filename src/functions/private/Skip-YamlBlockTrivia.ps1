function Skip-YamlBlockTrivia {
    <#
        .SYNOPSIS
        Advances past blank and comment-only block lines.

        .DESCRIPTION
        Moves the block reader context over empty lines and lines that contain only
        YAML comments. It validates comment text for forbidden byte order marks so
        block parsing can continue at the next content line.

        .EXAMPLE
        Skip-YamlBlockTrivia -Context $context

        Leaves the context line index at the next non-trivia block line.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Advances an in-memory parser context.'
    )]
    [CmdletBinding()]
    param (
        # The reader context whose LineIndex is advanced over block trivia.
        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    while ($Context.LineIndex -lt $Context.Lines.Count) {
        $line = $Context.Lines[$Context.LineIndex]
        $trimmed = $line.TrimStart(' ', "`t")
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
        break
    }
}
