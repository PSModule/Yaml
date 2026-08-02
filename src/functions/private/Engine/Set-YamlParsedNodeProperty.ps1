function Set-YamlParsedNodeProperty {
    <#
        .SYNOPSIS
        Applies parsed node properties and registers an anchor.

        .DESCRIPTION
        Copies parsed tag, unknown-tag, and anchor metadata onto a newly constructed
        YAML node. When an anchor is present, it records the node in the parser
        context so later aliases can resolve to the same representation object.

        .EXAMPLE
        Set-YamlParsedNodeProperty -Node $node -Tag 'tag:yaml.org,2002:str' -HasUnknownTag:$false -Anchor 'a1' -Context $context

        Applies scalar metadata and registers anchor a1 for subsequent alias lookup.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates an internal representation node during parsing.'
    )]
    [CmdletBinding()]
    param (
        # The newly parsed node that receives tag and anchor metadata.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # The expanded or resolved YAML tag associated with the node.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Tag,

        # Indicates whether the parsed tag is unknown to the supported schema.
        [Parameter(Mandatory)]
        [bool] $HasUnknownTag,

        # The parsed anchor name to store on the node and register, if any.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Anchor,

        # The parser context whose anchor table receives anchored nodes.
        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $Node.Tag = $Tag
    $Node.HasUnknownTag = $HasUnknownTag
    $Node.Anchor = $Anchor
    if (-not [string]::IsNullOrEmpty($Anchor)) {
        $Context.Anchors[$Anchor] = $Node
    }
}
