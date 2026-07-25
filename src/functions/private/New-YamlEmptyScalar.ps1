function New-YamlEmptyScalar {
    <#
        .SYNOPSIS
        Creates an empty implicit scalar node.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory representation node.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [int] $Depth,

        [Parameter(Mandatory)]
        [pscustomobject] $Mark,

        [AllowEmptyString()]
        [string] $Tag = '',

        [bool] $HasUnknownTag = $false,

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
