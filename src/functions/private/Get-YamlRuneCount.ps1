function Get-YamlRuneCount {
    <#
        .SYNOPSIS
        Counts Unicode scalar values in validated YAML text.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
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
