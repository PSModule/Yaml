function Test-YamlMappingValueIndicator {
    <#
        .SYNOPSIS
        Tests whether a colon is a mapping value indicator in the current context.

        .DESCRIPTION
        Checks a candidate colon and its following character using the YAML block and
        flow indicator rules. This prevents plain scalar colons from being mistaken
        for mapping separators while scanning key-value pairs.

        .EXAMPLE
        Test-YamlMappingValueIndicator -Text 'key: value' -Index 3

        Returns true because the colon is followed by YAML white space.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # Provides the source text containing the candidate colon and following character.
        [Parameter(Mandatory)]
        [string] $Text,

        # Identifies the zero-based position that must contain the colon to test.
        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [int] $Index,

        # Enables flow-collection punctuation rules for colons before comma or brackets.
        [Parameter()]
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
