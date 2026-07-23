function Test-YamlMappingValueIndicator {
    <#
        .SYNOPSIS
        Tests whether a colon is a mapping value indicator in the current context.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [int] $Index,

        [switch] $Flow
    )

    if ($Index -ge $Text.Length -or $Text[$Index] -cne ':') {
        return $false
    }
    if ($Index + 1 -ge $Text.Length) {
        return $true
    }

    $next = $Text[$Index + 1]
    if ((Test-YamlWhiteSpace -Character $next) -or $next -ceq "`n") {
        return $true
    }
    return $Flow -and $next -in @(',', '[', ']', '{', '}')
}
