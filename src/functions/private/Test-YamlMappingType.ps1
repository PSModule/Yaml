function Test-YamlMappingType {
    <#
        .SYNOPSIS
        Returns true when a value should be serialized as a YAML mapping.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter()] [AllowNull()] [object] $Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $true }
    if ($Value -is [string]) { return $false }
    if ($Value -is [System.ValueType]) { return $false }
    if ($Value -is [System.Collections.IEnumerable]) { return $false }
    if ($Value -is [psobject] -or $Value -is [System.Management.Automation.PSCustomObject]) { return $true }
    return $false
}
