function Test-YamlIndicator {
    <#
        .SYNOPSIS
        Tests whether text starts with a separated block indicator.

        .DESCRIPTION
        Verifies that a candidate block indicator appears at the beginning of the
        supplied text and is followed by separation or the end of the text. The
        scanner uses this to distinguish sequence and mapping indicators from scalars.

        .EXAMPLE
        Test-YamlIndicator -Text '- item' -Indicator '-'

        Returns true because the sequence indicator is followed by a space.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # Supplies the text fragment whose first character may be a block indicator.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        # Selects which YAML block indicator character is valid for this scanner branch.
        [Parameter(Mandatory)]
        [ValidateSet('-', '?', ':')]
        [string] $Indicator
    )

    if ($Text.Length -eq 0 -or -not $Text[0].Equals($Indicator[0])) {
        return $false
    }
    if ($Text.Length -eq 1) {
        return $true
    }
    return Test-YamlWhiteSpace -Character $Text[1]
}
