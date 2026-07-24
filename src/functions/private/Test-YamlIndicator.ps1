function Test-YamlIndicator {
    <#
        .SYNOPSIS
        Tests whether text starts with a separated block indicator.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

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
