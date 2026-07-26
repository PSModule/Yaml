function Add-YamlRemovalWork {
    <#
        .SYNOPSIS
        Charges deterministic operations to the YAML removal work budget.

        .DESCRIPTION
        Increments the shared work counter for expensive removal steps.
        Centralizing the charge keeps pointer resolution, coalescing, mutation,
        and validation on one deterministic budget and produces a
        location-aware exception when exceeded.

        .EXAMPLE
        Add-YamlRemovalWork -State $state -Count 3 -Operation 'target ordering' -Node $target.Node

        Charges three target-ordering operations and throws if the removal budget is exceeded.

        .LINK
        https://psmodule.io/Yaml/Functions/Remove-YamlEntry/
    #>
    [CmdletBinding()]
    param (
        # The shared state carries current and maximum work counts for the
        # removal invocation.
        [Parameter(Mandatory)]
        [pscustomobject] $State,

        # The operation cost is configurable because some steps charge a batch
        # of work at once.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $Count = 1,

        # The operation name explains which removal phase consumed the budget.
        [Parameter(Mandatory)]
        [string] $Operation,

        # The optional node anchors any budget exception to the YAML source
        # location.
        [Parameter()]
        [AllowNull()]
        [pscustomobject] $Node
    )

    $State.Count = [long] $State.Count + $Count
    if ($State.Count -le $State.MaxNodes) {
        return
    }

    $exception = New-YamlRemovalException -Node $Node `
        -ErrorId 'YamlRemovalWorkLimitExceeded' -Message (
        "YAML removal operation '$Operation' exceeded the configured invocation work " +
        "limit of $($State.MaxNodes) operations."
    )
    $exception.Data['YamlRemovalWorkCount'] = $State.Count
    $exception.Data['YamlRemovalWorkLimit'] = $State.MaxNodes
    $exception.Data['YamlRemovalWorkOperation'] = $Operation
    throw $exception
}
