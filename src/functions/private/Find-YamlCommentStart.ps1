function Find-YamlCommentStart {
    <#
        .SYNOPSIS
        Finds a comment indicator separated by YAML s-white.

        .DESCRIPTION
        Locates the first hash character that begins a YAML comment in a line
        fragment. Scanner helpers use this to distinguish scalar content from
        trailing comments without treating embedded hash characters as comments.

        .EXAMPLE
        Find-YamlCommentStart -Text 'value # comment'

        Returns the zero-based index where the trailing comment begins.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        # The line fragment to inspect for a YAML comment start.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    for ($index = 0; $index -lt $Text.Length; $index++) {
        if ($Text[$index] -ceq '#' -and (
                $index -eq 0 -or (Test-YamlWhiteSpace -Character $Text[$index - 1])
            )) {
            return $index
        }
    }
    return -1
}
