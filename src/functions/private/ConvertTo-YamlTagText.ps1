function ConvertTo-YamlTagText {
    <#
        .SYNOPSIS
        Encodes an effective tag as canonical YAML tag text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string] $Tag
    )

    $uriPunctuation = '#;/?:@&=+$,_.!~*''()[]'
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index -lt $Tag.Length; $index++) {
        $character = $Tag[$index]
        $code = [int] $character
        $isAsciiWord = (
            ($code -ge 0x30 -and $code -le 0x39) -or
            ($code -ge 0x41 -and $code -le 0x5A) -or
            ($code -ge 0x61 -and $code -le 0x7A) -or
            $character -eq '-'
        )
        if ($isAsciiWord -or $uriPunctuation.IndexOf($character) -ge 0) {
            [void] $builder.Append($character)
            continue
        }

        if ([char]::IsHighSurrogate($character)) {
            if ($index + 1 -ge $Tag.Length -or -not [char]::IsLowSurrogate($Tag[$index + 1])) {
                throw [System.ArgumentException]::new(
                    'A YAML tag cannot contain an unpaired UTF-16 high surrogate.'
                )
            }
            $scalarText = $Tag.Substring($index, 2)
            $index++
        } elseif ([char]::IsLowSurrogate($character)) {
            throw [System.ArgumentException]::new(
                'A YAML tag cannot contain an unpaired UTF-16 low surrogate.'
            )
        } else {
            $scalarText = [string] $character
        }

        foreach ($byte in $utf8.GetBytes($scalarText)) {
            [void] $builder.Append(('%{0:X2}' -f $byte))
        }
    }

    $escapedTag = $builder.ToString()
    $standardPrefix = 'tag:yaml.org,2002:'
    if ($escapedTag.StartsWith($standardPrefix, [System.StringComparison]::Ordinal)) {
        $suffix = $escapedTag.Substring($standardPrefix.Length)
        if (Test-YamlTagUriText -Text $suffix -Shorthand) {
            return "!!$suffix"
        }
    }
    return "!<$escapedTag>"
}
