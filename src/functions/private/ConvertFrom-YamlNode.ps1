function ConvertFrom-YamlNode {
    <#
        .SYNOPSIS
        Projects an internal YAML node graph to PowerShell values.
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[int, object]] $Cache,

        [switch] $AsHashtable
    )

    if ($Node.Kind -eq 'Alias') {
        Write-Output -InputObject (ConvertFrom-YamlNode -Node $Node.Target -Cache $Cache -AsHashtable:$AsHashtable) -NoEnumerate
        return
    }

    if ($Node.Kind -eq 'Scalar') {
        Write-Output -InputObject (Resolve-YamlScalar -Node $Node) -NoEnumerate
        return
    }

    if ($Cache.ContainsKey($Node.Id)) {
        Write-Output -InputObject ($Cache[$Node.Id]) -NoEnumerate
        return
    }

    if ($Node.Kind -eq 'Sequence') {
        if ($Node.Tag -eq 'tag:yaml.org,2002:omap') {
            $orderedMap = [System.Collections.Specialized.OrderedDictionary]::new()
            $Cache[$Node.Id] = $orderedMap
            foreach ($item in $Node.Items) {
                $entryMap = ConvertFrom-YamlNode -Node $item -Cache $Cache -AsHashtable
                $key = @($entryMap.Keys)[0]
                $orderedMap.Add($key, $entryMap[$key])
            }
            Write-Output -InputObject $orderedMap -NoEnumerate
            return
        }

        $isPairs = $Node.Tag -eq 'tag:yaml.org,2002:pairs'
        $sequence = [object[]]::new($Node.Items.Count)
        $Cache[$Node.Id] = $sequence
        for ($index = 0; $index -lt $Node.Items.Count; $index++) {
            $sequence[$index] = ConvertFrom-YamlNode -Node $Node.Items[$index] -Cache $Cache `
                -AsHashtable:($AsHashtable -or $isPairs)
        }
        Write-Output -InputObject $sequence -NoEnumerate
        return
    }

    $isSet = $Node.Tag -eq 'tag:yaml.org,2002:set'
    if ($AsHashtable -or $isSet) {
        $dictionary = [System.Collections.Specialized.OrderedDictionary]::new()
        $Cache[$Node.Id] = $dictionary
        foreach ($entry in $Node.Entries) {
            $key = ConvertFrom-YamlNode -Node $entry.Key -Cache $Cache -AsHashtable:$AsHashtable
            if ($null -eq $key) {
                $key = [System.DBNull]::Value
            }
            $entryValue = if ($isSet) {
                $null
            } else {
                ConvertFrom-YamlNode -Node $entry.Value -Cache $Cache -AsHashtable:$AsHashtable
            }
            $dictionary.Add($key, $entryValue)
        }
        Write-Output -InputObject $dictionary -NoEnumerate
        return
    }

    $result = [pscustomobject]@{}
    $Cache[$Node.Id] = $result
    $propertyNames = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    foreach ($entry in $Node.Entries) {
        $key = ConvertFrom-YamlNode -Node $entry.Key -Cache $Cache
        if ($key -isnot [string] -or [string]::IsNullOrEmpty($key)) {
            throw (New-YamlException -Start $entry.Key.Start -End $entry.Key.End -ErrorId 'YamlMappingKeyNotString' -Message (
                    'This mapping key cannot be represented as a PSCustomObject property. Use -AsHashtable.'
                ))
        }
        if (-not $propertyNames.Add($key)) {
            throw (New-YamlException -Start $entry.Key.Start -End $entry.Key.End -ErrorId 'YamlPropertyNameCollision' -Message (
                    "The mapping keys contain a case-insensitive property collision for '$key'. Use -AsHashtable."
                ))
        }
        $entryValue = ConvertFrom-YamlNode -Node $entry.Value -Cache $Cache
        $property = [System.Management.Automation.PSNoteProperty]::new($key, $entryValue)
        $result.PSObject.Properties.Add($property)
    }
    Write-Output -InputObject $result -NoEnumerate
}
