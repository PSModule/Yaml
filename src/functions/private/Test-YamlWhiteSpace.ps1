function Test-YamlWhiteSpace {
    <#
        .SYNOPSIS
        Tests the YAML s-white production.

        .DESCRIPTION
        Returns true only for space and tab, the characters YAML treats as white
        space. Scanner predicates use this to skip separation without consuming
        line breaks.

        .EXAMPLE
        Test-YamlWhiteSpace -Character ([char]0x09)

        Returns true because a tab is YAML white space.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # Supplies the single character to classify as YAML white space or not.
        [Parameter(Mandatory)]
        [char] $Character
    )

    return $Character -ceq ' ' -or $Character -ceq "`t"
}
