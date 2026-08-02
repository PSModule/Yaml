function New-YamlValueBox {
    <#
        .SYNOPSIS
        Boxes an internal value so PowerShell never enumerates it in transit.

        .DESCRIPTION
        Wraps a constructed YAML value in a single-property carrier object so that
        arrays and other collections pass through the parser call chain without
        PowerShell unrolling them onto the pipeline.

        .EXAMPLE
        New-YamlValueBox -Value @(1, 2, 3)

        Returns a box whose Value property holds the array intact.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory value box.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The value to carry without pipeline enumeration; null is allowed.
        [Parameter()]
        [AllowNull()]
        [object] $Value
    )

    [pscustomobject]@{
        PSTypeName = 'PSModule.Yaml.ValueBox'
        Value      = $Value
    }
}
