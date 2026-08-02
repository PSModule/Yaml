function ConvertTo-YamlQuotedText {
    <#
        .SYNOPSIS
        Encodes a string as a YAML double-quoted scalar.

        .DESCRIPTION
        Escapes string content for a YAML double-quoted scalar, including control
        characters and invalid UTF-16 surrogate detection. It is used when plain
        scalar output would be ambiguous or unsafe.

        .EXAMPLE
        ConvertTo-YamlQuotedText -Value "line`nbreak"

        Returns a YAML double-quoted scalar with required escape sequences.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The scalar content to quote while preserving empty strings exactly.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value
    )

    $builder = [System.Text.StringBuilder]::new()
    [void] $builder.Append('"')
    for ($index = 0; $index -lt $Value.Length; $index++) {
        $character = $Value[$index]
        $code = [int] $character
        if ([char]::IsHighSurrogate($character)) {
            if ($index + 1 -ge $Value.Length -or -not [char]::IsLowSurrogate($Value[$index + 1])) {
                throw [System.ArgumentException]::new(
                    'A YAML string cannot contain an unpaired UTF-16 high surrogate.'
                )
            }
            [void] $builder.Append($character)
            [void] $builder.Append($Value[++$index])
        } elseif ([char]::IsLowSurrogate($character)) {
            throw [System.ArgumentException]::new(
                'A YAML string cannot contain an unpaired UTF-16 low surrogate.'
            )
        } elseif ($code -eq 0) {
            [void] $builder.Append('\0')
        } elseif ($code -eq 7) {
            [void] $builder.Append('\a')
        } elseif ($code -eq 8) {
            [void] $builder.Append('\b')
        } elseif ($code -eq 9) {
            [void] $builder.Append('\t')
        } elseif ($code -eq 10) {
            [void] $builder.Append('\n')
        } elseif ($code -eq 11) {
            [void] $builder.Append('\v')
        } elseif ($code -eq 12) {
            [void] $builder.Append('\f')
        } elseif ($code -eq 13) {
            [void] $builder.Append('\r')
        } elseif ($code -eq 27) {
            [void] $builder.Append('\e')
        } elseif ($code -eq 34) {
            [void] $builder.Append('\"')
        } elseif ($code -eq 92) {
            [void] $builder.Append('\\')
        } elseif ($code -lt 0x20 -or $code -eq 0x7F -or $code -eq 0xFEFF -or
            $code -eq 0xFFFE -or $code -eq 0xFFFF -or
            ($code -ge 0x80 -and $code -le 0x9F)) {
            [void] $builder.Append(('\u{0:X4}' -f $code))
        } else {
            [void] $builder.Append($character)
        }
    }
    [void] $builder.Append('"')
    return $builder.ToString()
}
