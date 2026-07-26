function Get-YamlRuneCount {
    <#
        .SYNOPSIS
        Counts Unicode scalar values in validated YAML text.

        .DESCRIPTION
        Walks validated text by System.Text.Rune so surrogate pairs count as one
        YAML character. Parser limits use this helper when they are defined in
        Unicode scalar values instead of UTF-16 code units.

        .EXAMPLE
        Get-YamlRuneCount -Text 'a😀'

        Returns 2 because the emoji is one Unicode scalar value.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        # Supplies already validated YAML text so rune iteration can count characters safely.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $count = 0
    $index = 0
    while ($index -lt $Text.Length) {
        $rune = [System.Text.Rune]::GetRuneAt($Text, $index)
        $index += $rune.Utf16SequenceLength
        $count++
    }
    return $count
}
