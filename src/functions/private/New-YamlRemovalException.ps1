function New-YamlRemovalException {
    <#
        .SYNOPSIS
        Creates a classified exception for a YAML removal failure.

        .DESCRIPTION
        Wraps removal failures in the module's YAML exception shape with the
        correct error id and source marks. It falls back to a zero mark when no
        node is available so budget and pointer parse failures remain
        classified.

        .EXAMPLE
        New-YamlRemovalException -ErrorId 'YamlRemovalPathNotFound' -Message 'The path was not found.' -Node $node

        Returns a classified exception whose source marks point at the supplied node.

        .LINK
        https://psmodule.io/Yaml/Functions/Remove-YamlEntry/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory exception without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([System.FormatException])]
    param (
        # The removal-specific error id classifies the failure for callers and
        # tests.
        [Parameter(Mandatory)]
        [string] $ErrorId,

        # The message explains the exact pointer, graph, or budget problem to
        # report.
        [Parameter(Mandatory)]
        [string] $Message,

        # The node supplies source marks when a graph location exists; null
        # failures use a synthetic mark.
        [Parameter()]
        [AllowNull()]
        [pscustomobject] $Node
    )

    if ($null -eq $Node) {
        $mark = New-YamlMark -Index 0 -Line 0 -Column 0
        return New-YamlException -Start $mark -End $mark -ErrorId $ErrorId -Message $Message
    }

    return New-YamlException -Start $Node.Start -End $Node.End `
        -ErrorId $ErrorId -Message $Message
}
