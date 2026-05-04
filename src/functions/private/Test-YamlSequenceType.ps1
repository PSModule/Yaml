function Test-YamlSequenceType {
    <#
        .SYNOPSIS
        Returns true when a value should be serialized as a YAML sequence.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param([Parameter()] [AllowNull()] [object] $Value)

    if ($null -eq $Value) { return $false }
    if ($Value -is [string]) { return $false }
    if ($Value -is [System.Collections.IDictionary]) { return $false }
    if ($Value -is [System.Collections.IEnumerable]) { return $true }
    return $false
}
