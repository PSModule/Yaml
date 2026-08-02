function New-YamlEmptyScalar {
    <#
        .SYNOPSIS
        Creates an empty implicit scalar node.

        .DESCRIPTION
        Allocates the scalar node used when YAML grammar permits an omitted value,
        such as an empty document or mapping value. It applies parsed tag and anchor
        metadata while preserving parser budgets through New-YamlSyntaxNode.

        .EXAMPLE
        New-YamlEmptyScalar -Context $context -Depth 1 -Mark $mark -Tag '' -HasUnknownTag:$false -Anchor ''

        Returns a plain scalar node whose value is an empty string.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory representation node.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The parser context that supplies resource limits and anchor state.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # The nesting depth to charge when the empty scalar node is allocated.
        [Parameter(Mandatory)]
        [int] $Depth,

        # The source mark used as both the start and end of the omitted value.
        [Parameter(Mandatory)]
        [pscustomobject] $Mark,

        # The resolved or explicit tag parsed for the empty scalar, if present.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Tag = '',

        # Whether the parsed tag is an application tag unknown to the core schema.
        [Parameter()]
        [bool] $HasUnknownTag = $false,

        # The anchor name to register for later alias resolution, if present.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Anchor = ''
    )

    $node = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth $Depth -Start $Mark -End $Mark
    Set-YamlParsedNodeProperty -Node $node -Tag $Tag -HasUnknownTag $HasUnknownTag -Anchor $Anchor `
        -Context $Context
    $node.Value = ''
    $node.Style = 'Plain'
    $node.IsPlainImplicit = [string]::IsNullOrEmpty($Tag) -and -not $HasUnknownTag
    return $node
}
