function Skip-YamlDocumentPrefix {
    <#
        .SYNOPSIS
        Advances across repeated YAML document prefixes.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Advances an in-memory parser context.'
    )]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [switch] $RequireDocumentStart
    )

    $validatedPrefix = $false
    do {
        $lineIndex = $Context.LineIndex
        $consumedByteOrderMark = $false
        if ($lineIndex -lt $Context.Lines.Count -and
            $Context.Lines[$lineIndex].StartsWith(
                [string] [char] 0xFEFF,
                [System.StringComparison]::Ordinal
            )) {
            $atStreamStart = $Context.LineStarts[$lineIndex] -eq 0
            if ($atStreamStart -or $validatedPrefix -or
                (Test-YamlDocumentByteOrderMark -Context $Context `
                    -RequireDocumentStart:$RequireDocumentStart)) {
                Read-YamlDocumentByteOrderMark -Context $Context `
                    -RequireDocumentStart:$RequireDocumentStart -SkipValidation
                $consumedByteOrderMark = $true
                if (-not $atStreamStart) {
                    $validatedPrefix = $true
                }
            }
        }
        Skip-YamlBlockTrivia -Context $Context
    } while (
        $Context.LineIndex -ne $lineIndex -or
        $consumedByteOrderMark
    )
}
