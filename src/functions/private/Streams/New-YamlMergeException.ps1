function New-YamlMergeException {
    <#
        .SYNOPSIS
        Creates a classified exception for a YAML merge failure.

        .DESCRIPTION
        Creates the YAML-specific exception used when merge policies or resource
        budgets fail. It attaches the relevant node marks when available so public
        errors point at the offending YAML location.

        .EXAMPLE
        New-YamlMergeException -ErrorId 'YamlMergeConflict' -Message 'YAML merge conflict at $.name.' -Node $overlayNode

        Returns a classified format exception anchored to the overlay node's
        source span.

        .LINK
        https://psmodule.io/Yaml/Functions/Streams/Merge-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory exception without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([System.FormatException])]
    param (
        # Identifies the merge failure class for callers and tests.
        [Parameter(Mandatory)]
        [string] $ErrorId,

        # Explains the merge failure with context-specific details.
        [Parameter(Mandatory)]
        [string] $Message,

        # Provides source marks for location-aware diagnostics when available.
        [Parameter()]
        [AllowNull()]
        [pscustomobject] $Node
    )

    if ($null -eq $Node) {
        $mark = New-YamlMark -Index 0 -Line 0 -Column 0
        return New-YamlException -Start $mark -End $mark -ErrorId $ErrorId -Message $Message
    }

    return New-YamlException -Start $Node.Start -End $Node.End -ErrorId $ErrorId -Message $Message
}
