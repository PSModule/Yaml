function New-YamlSyntaxNode {
    <#
        .SYNOPSIS
        Creates a context-aware syntax token with enforced parser budgets.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory syntax token.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [ValidateSet('Alias', 'Mapping', 'Scalar', 'Sequence')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [int] $Depth,

        [Parameter(Mandatory)]
        [pscustomobject] $Start,

        [Parameter(Mandatory)]
        [pscustomobject] $End
    )

    if ($Depth -gt $Context.MaxDepth) {
        throw (New-YamlException -Start $Start -End $End -ErrorId 'YamlDepthExceeded' -Message (
                "The YAML nesting depth exceeds the configured limit of $($Context.MaxDepth)."
            ))
    }
    $Context.NodeCount++
    if ($Context.NodeCount -gt $Context.MaxNodes) {
        throw (New-YamlException -Start $Start -End $End -ErrorId 'YamlNodeLimitExceeded' -Message (
                "The YAML stream exceeds the configured limit of $($Context.MaxNodes) nodes."
            ))
    }

    $node = New-YamlNode -Id $Context.NextId -Kind $Kind -Start $Start -End $End
    $node.PSObject.TypeNames.Insert(0, 'PSModule.Yaml.SyntaxToken')
    $Context.NextId++
    $node.MaxNumericLength = $Context.MaxNumericLength
    Write-Output -InputObject $node -NoEnumerate
}
