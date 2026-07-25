function Test-YamlWhiteSpace {
    <#
        .SYNOPSIS
        Tests the YAML s-white production.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [char] $Character
    )

    return $Character -ceq ' ' -or $Character -ceq "`t"
}
