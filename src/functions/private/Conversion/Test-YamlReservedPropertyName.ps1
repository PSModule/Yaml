function Test-YamlReservedPropertyName {
    <#
        .SYNOPSIS
        Tests whether a property name is reserved by PowerShell ETS.

        .DESCRIPTION
        Compares a mapping key against Extended Type System member names that
        PowerShell reserves on projected objects. The projector uses this to avoid
        creating ambiguous PSCustomObject properties.

        .EXAMPLE
        Test-YamlReservedPropertyName -Name 'PSObject'

        Returns true because PSObject is reserved by PowerShell ETS.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # Provides the candidate property name before it is added to a projected object.
        [Parameter(Mandatory)]
        [string] $Name
    )

    foreach ($reservedName in @(
            'PSObject',
            'PSTypeNames',
            'PSBase',
            'PSAdapted',
            'PSExtended'
        )) {
        if ($Name.Equals($reservedName, [System.StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}
