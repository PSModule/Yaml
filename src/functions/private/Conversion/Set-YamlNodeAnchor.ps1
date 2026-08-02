function Set-YamlNodeAnchor {
    <#
        .SYNOPSIS
        Assigns deterministic anchors to repeated emission nodes.

        .DESCRIPTION
        Walks the tracked reference order and assigns stable generated anchor names
        to nodes that are referenced more than once. The YAML pipeline uses these
        anchors so repeated graph nodes can be represented consistently.

        .EXAMPLE
        Set-YamlNodeAnchor -State $state

        Updates repeated nodes in the state with deterministic id-style anchor names.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Assigns anchors within a private in-memory representation graph.'
    )]
    [CmdletBinding()]
    param (
        # The graph state containing reference order, reference counts, and nodes by id.
        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    $anchorNumber = 1
    foreach ($referenceId in $State.ReferenceOrder) {
        if ($State.ReferenceCounts[$referenceId] -gt 1) {
            $State.NodesById[$referenceId].Anchor = 'id{0:d3}' -f $anchorNumber
            $anchorNumber++
        }
    }
}
