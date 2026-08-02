function Test-YamlSerializationReference {
    <#
        .SYNOPSIS
        Tests whether a value participates in YAML anchor identity.

        .DESCRIPTION
        Identifies values whose identity can affect YAML graph emission, such as dictionaries,
        arrays, custom objects, and object wrappers. The serializer uses this to decide which nodes
        need reference tracking for anchors and aliases.

        .EXAMPLE
        Test-YamlSerializationReference -Value ([pscustomobject]@{ Name = 'Ada' })

        Returns true because the custom object can participate in YAML anchor identity.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # The candidate value is tested so only identity-bearing nodes enter reference tracking.
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $false
    }
    if ($Value -is [byte[]] -or
        $Value -is [System.Collections.IDictionary] -or
        $Value -is [System.Management.Automation.PSCustomObject]) {
        return $true
    }
    if ($Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [string] -and
        $Value -isnot [char]) {
        return $true
    }
    return $Value.GetType() -eq [object]
}
