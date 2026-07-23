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

    $separators = if ($Indicator -eq '-') { @(' ', "`t") } else { @(' ') }
    return $Text.Length -gt 0 -and $Text[0] -eq $Indicator[0] -and (
        $Text.Length -eq 1 -or $Text[1] -in $separators
    )
}
