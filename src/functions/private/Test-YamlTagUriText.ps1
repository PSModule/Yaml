function Test-YamlTagUriText {
    <#
        .SYNOPSIS
        Tests tag URI text without allocating a decoded copy.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [switch] $Shorthand
    )

    if ($Text.Length -eq 0) {
        return $false
    }

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ([char]::IsWhiteSpace($character) -or [char]::IsControl($character) -or
            $character -in @('<', '>', '{', '}')) {
            return $false
        }
        if ($Shorthand -and $character -in @('!', '[', ']', ',')) {
            return $false
        }
        if ($character -ne '%') {
            continue
        }
        if ($index + 2 -ge $Text.Length -or
            $Text[$index + 1] -notmatch '^[0-9A-Fa-f]$' -or
            $Text[$index + 2] -notmatch '^[0-9A-Fa-f]$') {
            return $false
        }
        $index += 2
    }
    return $true
}
