function Test-YamlReservedPropertyName {
    <#
        .SYNOPSIS
        Tests whether a property name is reserved by PowerShell ETS.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
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
