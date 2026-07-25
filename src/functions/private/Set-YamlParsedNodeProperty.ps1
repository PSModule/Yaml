function Set-YamlParsedNodeProperty {
    <#
        .SYNOPSIS
        Applies parsed node properties and registers an anchor.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates an internal representation node during parsing.'
    )]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Tag,

        [Parameter(Mandatory)]
        [bool] $HasUnknownTag,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Anchor,

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
