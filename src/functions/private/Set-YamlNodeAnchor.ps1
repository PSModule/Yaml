function Set-YamlNodeAnchor {
    <#
        .SYNOPSIS
        Assigns deterministic anchors to repeated emission nodes.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Assigns anchors within a private in-memory representation graph.'
    )]
    [CmdletBinding()]
    param (
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
