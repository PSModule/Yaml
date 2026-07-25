function ConvertTo-YamlRepresentationText {
    <#
        .SYNOPSIS
        Emits representation documents as deterministic LF-normalized YAML.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Documents,

        [Parameter(Mandatory)]
        [ValidateRange(2, 9)]
        [int] $Indent
    )

    if ($Documents.Count -eq 0) {
        return ''
    }

    $state = [pscustomobject]@{ NextAnchor = 1 }
    $renderedDocuments = [System.Collections.Generic.List[string]]::new()
    foreach ($document in $Documents) {
        $emissionNode = ConvertTo-YamlRepresentationNode -Node $document -State $state
        $text = ConvertTo-YamlText -Node $emissionNode -Indent $Indent -ExplicitDocumentStart
        $text = $text -replace '[ \t]+(?=\n|$)', ''
        $renderedDocuments.Add($text.TrimEnd("`n"))
    }
    return $renderedDocuments.ToArray() -join "`n"
}
