function Add-YamlMergeWork {
    <#
        .SYNOPSIS
        Charges one or more deterministic operations to the YAML merge work budget.
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

    $exception = New-YamlMergeException -Node $Node -ErrorId 'YamlMergeWorkLimitExceeded' `
        -Message (
        "YAML merge operation '$Operation' exceeded the configured invocation work limit " +
        "of $($State.MaxNodes) operations."
    )
    $exception.Data['YamlMergeWorkCount'] = $State.Count
    $exception.Data['YamlMergeWorkLimit'] = $State.MaxNodes
    throw $exception
}
