function Test-YamlSerializationReference {
    <#
        .SYNOPSIS
        Tests whether a value participates in YAML anchor identity.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
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
