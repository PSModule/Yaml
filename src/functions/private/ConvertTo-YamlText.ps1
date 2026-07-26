function ConvertTo-YamlText {
    <#
        .SYNOPSIS
        Emits an internal node graph as LF-normalized YAML text.

        .DESCRIPTION
        Serializes a normalized emission node graph to a YAML document using LF
        line endings and the configured indentation. It centralizes final text
        assembly so document markers, anchors, and aliases are emitted consistently.

        .EXAMPLE
        ConvertTo-YamlText -Node $emissionNode -Indent 2 -ExplicitDocumentStart

        Returns YAML text for the emission graph with an explicit document start marker.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The root emission graph to write as one YAML document.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # Number of spaces per nesting level for deterministic block output.
        [Parameter(Mandatory)]
        [ValidateRange(2, 9)]
        [int] $Indent,

        # Allows callers to include the YAML document-start marker when required.
        [Parameter()]
        [switch] $ExplicitDocumentStart
    )

    $builder = [System.Text.StringBuilder]::new()
    if ($ExplicitDocumentStart) {
        [void] $builder.Append("---`n")
    }
    Write-YamlNodeText -Builder $builder -Node $Node -Level 0 -Indent $Indent `
        -EmittedReferences ([System.Collections.Generic.HashSet[long]]::new())
    return $builder.ToString()
}
