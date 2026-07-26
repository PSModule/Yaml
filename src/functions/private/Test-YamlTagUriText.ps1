function Test-YamlTagUriText {
    <#
        .SYNOPSIS
        Tests tag URI text without allocating a decoded copy.

        .DESCRIPTION
        Validates the character set and percent-escape pairs permitted in YAML tag
        URI text. The check runs against the original token so tag resolution can
        reject malformed tags before decoding or expanding them.

        .EXAMPLE
        Test-YamlTagUriText -Text 'tag:example.com,2026:settings'

        Returns true because the text uses characters allowed in YAML tag URI text.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # Supplies the raw tag URI text whose characters and escapes must be validated.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        # Applies stricter shorthand-suffix exclusions before a tag handle is expanded.
        [Parameter()]
        [switch] $Shorthand
    )

    if ($Text.Length -eq 0) {
        return $false
    }

    $uriPunctuation = '#;/?:@&=+$,_.!~*''()[]'
    $shorthandExcluded = '!,[]'
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if (-not $character.Equals([char] '%')) {
            $code = [int] $character
            $isWordCharacter = (
                ($code -ge 0x30 -and $code -le 0x39) -or
                ($code -ge 0x41 -and $code -le 0x5A) -or
                ($code -ge 0x61 -and $code -le 0x7A) -or
                $character.Equals([char] '-')
            )
            if (-not $isWordCharacter -and $uriPunctuation.IndexOf($character) -lt 0) {
                return $false
            }
            if ($Shorthand -and $shorthandExcluded.IndexOf($character) -ge 0) {
                return $false
            }
            continue
        }

        if ($index + 2 -ge $Text.Length) {
            return $false
        }
        foreach ($offset in 1, 2) {
            $hexCode = [int] $Text[$index + $offset]
            if (-not (
                    ($hexCode -ge 0x30 -and $hexCode -le 0x39) -or
                    ($hexCode -ge 0x41 -and $hexCode -le 0x46) -or
                    ($hexCode -ge 0x61 -and $hexCode -le 0x66)
                )) {
                return $false
            }
        }
        $index += 2
    }
    return $true
}
