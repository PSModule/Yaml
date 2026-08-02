function Read-YamlBoundedEnumerable {
    <#
        .SYNOPSIS
        Materializes only as many enumerable items as the node budget permits.

        .DESCRIPTION
        Enumerates a PowerShell collection while reserving node budget before
        each item is retained. This prevents YAML graph processing from holding
        more values than the configured resource limits can safely handle.

        .EXAMPLE
        Read-YamlBoundedEnumerable -Value $items -MaxNodes 100000 -State $state -NodesPerItem 1

        Returns a list containing only items admitted by the current node budget.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param (
        # Enumerable whose items must be inspected before materialization.
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable] $Value,

        # Configured node limit used in resource-limit error messages.
        [Parameter(Mandatory)]
        [int] $MaxNodes,

        # Mutable graph-processing state that tracks used and reserved nodes.
        [Parameter(Mandatory)]
        [pscustomobject] $State,

        # Treats each item as a dictionary entry so key and value are inspected.
        [Parameter()]
        [switch] $DictionaryEntries,

        # Preserves the caller's enum handling mode during item inspection.
        [Parameter()]
        [switch] $EnumsAsStrings,

        # Reserves extra nodes for items that expand into more than one node.
        [Parameter()]
        [ValidateRange(1, 2)]
        [int] $NodesPerItem = 1
    )

    $availableNodes = $State.MaxNodes - $State.NodeCount - $State.ReservedNodeCount
    if ($Value -is [System.Collections.ICollection] -and
        ([long] $Value.Count * $NodesPerItem) -gt $availableNodes) {
        throw (New-YamlSerializationException -ErrorId 'YamlNodeLimitExceeded' -Message (
                "The object graph exceeds the configured limit of $MaxNodes nodes."
            ))
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $enumerator = $Value.GetEnumerator()
    try {
        while ($enumerator.MoveNext()) {
            if (($State.NodeCount + $State.ReservedNodeCount + $NodesPerItem) -gt $MaxNodes) {
                throw (New-YamlSerializationException -ErrorId 'YamlNodeLimitExceeded' -Message (
                        "The object graph exceeds the configured limit of $MaxNodes nodes."
                    ))
            }
            $item = [object] $enumerator.Current
            if ($DictionaryEntries) {
                $null = Get-YamlSerializationShape -Value $item.Key -State $State `
                    -EnumsAsStrings:$EnumsAsStrings -InspectOnly
                $null = Get-YamlSerializationShape -Value $item.Value -State $State `
                    -EnumsAsStrings:$EnumsAsStrings -InspectOnly
            } else {
                $null = Get-YamlSerializationShape -Value $item -State $State `
                    -EnumsAsStrings:$EnumsAsStrings -InspectOnly
            }
            $State.ReservedNodeCount += $NodesPerItem
            $items.Add($item)
        }
    } finally {
        if ($enumerator -is [System.IDisposable]) {
            $enumerator.Dispose()
        }
    }
    Write-Output -InputObject $items -NoEnumerate
}
