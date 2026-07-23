function New-YamlValueBox {
    <#
        .SYNOPSIS
        Boxes an internal value so PowerShell never enumerates it in transit.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory value box.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    [pscustomobject]@{
        PSTypeName = 'PSModule.Yaml.ValueBox'
        Value      = $Value
    }
}
