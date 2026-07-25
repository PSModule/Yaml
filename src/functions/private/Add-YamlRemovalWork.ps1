function Add-YamlRemovalWork {
    <#
        .SYNOPSIS
        Charges deterministic operations to the YAML removal work budget.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $State,

        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $Count = 1,

        [Parameter(Mandatory)]
        [string] $Operation,

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
