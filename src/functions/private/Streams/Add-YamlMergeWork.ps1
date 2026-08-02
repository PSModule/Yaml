function Add-YamlMergeWork {
    <#
        .SYNOPSIS
        Charges one or more deterministic operations to the YAML merge work budget.

        .DESCRIPTION
        Increments the invocation work counter for deterministic merge operations
        such as indexing, fingerprinting, equality checks, and cloning. This
        centralizes budget enforcement so adversarial graphs cannot make merge
        processing unbounded.

        .EXAMPLE
        Add-YamlMergeWork -State $mergeContext.WorkState -Count 3 -Operation 'index rebuild' -Node $node

        Charges three index rebuild operations to the merge budget and throws if
        the configured limit is exceeded.

        .LINK
        https://psmodule.io/Yaml/Functions/Streams/Merge-Yaml/
    #>
    [CmdletBinding()]
    param (
        # Shared work budget state records total charged operations.
        [Parameter(Mandatory)]
        [pscustomobject] $State,

        # Allows callers to charge batched deterministic work without repeated calls.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $Count = 1,

        # Names the work being charged for precise limit diagnostics.
        [Parameter(Mandatory)]
        [string] $Operation,

        # Supplies source location for limit errors when a specific graph node caused the work.
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
