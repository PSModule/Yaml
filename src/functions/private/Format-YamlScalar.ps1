function Format-YamlScalar {
    <#
        .SYNOPSIS
        Renders a scalar value as a YAML token.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter()] [AllowNull()] [object] $Value,
        [Parameter(Mandatory)] [pscustomobject] $Options
    )

    if ($null -eq $Value) { return 'null' }

    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }

    if ($Value -is [System.Enum]) {
        if ($Options.EnumsAsStrings) {
            return Format-YamlString -Text ($Value.ToString())
        }
        return ([int64] $Value).ToString([cultureinfo]::InvariantCulture)
    }

    if ($Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int] -or $Value -is [uint32] -or
        $Value -is [long] -or $Value -is [uint64]) {
        return ([System.IConvertible] $Value).ToString([cultureinfo]::InvariantCulture)
    }

    if ($Value -is [single] -or $Value -is [double] -or $Value -is [decimal]) {
        return ([System.IConvertible] $Value).ToString([cultureinfo]::InvariantCulture)
    }

    if ($Value -is [datetime]) {
        return $Value.ToString('o', [cultureinfo]::InvariantCulture)
    }

    return Format-YamlString -Text ([string] $Value)
}
