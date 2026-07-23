function Find-YamlCommentStart {
    <#
        .SYNOPSIS
        Finds a comment indicator separated by YAML s-white.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
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
