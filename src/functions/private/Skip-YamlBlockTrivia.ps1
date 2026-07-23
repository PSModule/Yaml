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
        if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#', [System.StringComparison]::Ordinal)) {
            $Context.LineIndex++
            continue
        }
        break
    }
}
