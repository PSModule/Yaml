function New-YamlSyntaxNode {
    <#
        .SYNOPSIS
        Creates a context-aware syntax token with enforced parser budgets.

        .DESCRIPTION
        Checks configured depth and node-count limits before allocating a YAML node.
        Reader helpers use this wrapper so oversized ConvertFrom-Yaml input fails
        with YAML-specific diagnostics at the node source range.

        .EXAMPLE
        New-YamlSyntaxNode -Context $context -Kind Mapping -Depth 2 -Start $start -End $end

        Returns a mapping syntax token and increments the parser node counters.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory syntax token.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The parser context that owns node identifiers, counters, and limits.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # The syntax node kind requested by the active YAML reader.
        [Parameter(Mandatory)]
        [ValidateSet('Alias', 'Mapping', 'Scalar', 'Sequence')]
        [string] $Kind,

        # The current nesting depth to compare against the configured maximum.
        [Parameter(Mandatory)]
        [int] $Depth,

        # The source mark where the node begins for limit and parse errors.
        [Parameter(Mandatory)]
        [pscustomobject] $Start,

        # The source mark where the node ends for limit and parse errors.
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
