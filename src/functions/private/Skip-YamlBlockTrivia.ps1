function Skip-YamlBlockTrivia {
    <#
        .SYNOPSIS
        Advances past blank and comment-only block lines.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Advances an in-memory parser context.'
    )]
    [CmdletBinding()]
    param (
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
