function Read-YamlBoundedEnumerable {
    <#
        .SYNOPSIS
        Materializes only as many enumerable items as the node budget permits.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[object]])]
    param (
        [Parameter(Mandatory)]
        [System.Collections.IEnumerable] $Value,

        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [int] $MaximumItems,

        [Parameter(Mandatory)]
        [int] $MaxNodes,

        [Parameter(Mandatory)]
        [pscustomobject] $State,

        [switch] $DictionaryEntries,

        [switch] $EnumsAsStrings
    )

    if ($Value -is [System.Collections.ICollection] -and
        $Value.Count -gt $MaximumItems) {
        throw (New-YamlSerializationException -ErrorId 'YamlNodeLimitExceeded' -Message (
                "The object graph exceeds the configured limit of $MaxNodes nodes."
            ))
    }

    $items = [System.Collections.Generic.List[object]]::new()
    $enumerator = $Value.GetEnumerator()
    try {
        while ($enumerator.MoveNext()) {
            if ($items.Count -ge $MaximumItems) {
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
            $items.Add($item)
        }
    } finally {
        if ($enumerator -is [System.IDisposable]) {
            $enumerator.Dispose()
        }
    }
    Write-Output -InputObject $items -NoEnumerate
}
