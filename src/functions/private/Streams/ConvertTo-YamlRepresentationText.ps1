function ConvertTo-YamlRepresentationText {
    <#
        .SYNOPSIS
        Emits representation documents as deterministic LF-normalized YAML.

        .DESCRIPTION
        Converts composed representation documents into deterministic YAML text
        without projecting through public PowerShell values. It supports
        representation-preserving commands that must retain tags, anchors, and aliases.

        .EXAMPLE
        ConvertTo-YamlRepresentationText -Documents $documents -Indent 2

        Returns the formatted YAML stream for all supplied representation documents.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The representation document roots to emit in their original stream order.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Documents,

        # Number of spaces per nesting level for deterministic block output.
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
