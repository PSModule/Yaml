function ConvertFrom-YamlTagUriEscape {
    <#
        .SYNOPSIS
        Decodes YAML tag URI %xx escapes as UTF-8.

        .DESCRIPTION
        Converts percent-escaped byte sequences from a YAML tag token into strict
        UTF-8 text while preserving unescaped characters. It reports malformed
        escapes, invalid UTF-8, and decoded tag length overflows as YAML errors.

        .EXAMPLE
        ConvertFrom-YamlTagUriEscape -Text 'tag%3Atest' -Mark (New-YamlMark -Index 0 -Line 0 -Column 0) -Token '!<tag%3Atest>' -MaxLength 1024

        Decodes the escaped colon and returns tag:test.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The tag URI text to decode before tag resolution continues.
        [Parameter(Mandatory)]
        [string] $Text,

        # The token location to attach to any malformed escape or length error.
        [Parameter(Mandatory)]
        [pscustomobject] $Mark,

        # The original tag token to include in diagnostics for invalid escapes.
        [Parameter(Mandatory)]
        [string] $Token,

        # The decoded tag length budget that prevents oversized expanded tags.
        [Parameter(Mandatory)]
        [ValidateRange(1, 1048576)]
        [int] $MaxLength
    )

    $builder = [System.Text.StringBuilder]::new()
    $escapedBytes = [System.Collections.Generic.List[byte]]::new()
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($character -ne '%') {
            if ($escapedBytes.Count -gt 0) {
                try {
                    $decoded = $utf8.GetString($escapedBytes.ToArray())
                } catch [System.Text.DecoderFallbackException] {
                    throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                            "The tag token '$Token' contains an invalid UTF-8 escape sequence."
                        ))
                }
                if ($builder.Length + $decoded.Length -gt $MaxLength) {
                    throw (New-YamlException -Start $Mark -End $Mark `
                            -ErrorId 'YamlTagLimitExceeded' -Message (
                            "A YAML tag exceeds the configured limit of $MaxLength characters."
                        ))
                }
                [void] $builder.Append($decoded)
                $escapedBytes.Clear()
            }
            if ($builder.Length -ge $MaxLength) {
                throw (New-YamlException -Start $Mark -End $Mark `
                        -ErrorId 'YamlTagLimitExceeded' -Message (
                        "A YAML tag exceeds the configured limit of $MaxLength characters."
                    ))
            }
            [void] $builder.Append($character)
            continue
        }

        if ($index + 2 -ge $Text.Length) {
            throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                    "The tag token '$Token' contains a malformed percent escape."
                ))
        }
        $pair = '{0}{1}' -f $Text[$index + 1], $Text[$index + 2]
        if ($pair -cnotmatch '^[0-9A-Fa-f]{2}$') {
            throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                    "The tag token '$Token' contains a malformed percent escape."
                ))
        }
        $escapedBytes.Add([System.Convert]::ToByte($pair, 16))
        $index += 2
    }

    if ($escapedBytes.Count -gt 0) {
        try {
            $decoded = $utf8.GetString($escapedBytes.ToArray())
        } catch [System.Text.DecoderFallbackException] {
            throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                    "The tag token '$Token' contains an invalid UTF-8 escape sequence."
                ))
        }
        if ($builder.Length + $decoded.Length -gt $MaxLength) {
            throw (New-YamlException -Start $Mark -End $Mark `
                    -ErrorId 'YamlTagLimitExceeded' -Message (
                    "A YAML tag exceeds the configured limit of $MaxLength characters."
                ))
        }
        [void] $builder.Append($decoded)
    }

    $builder.ToString()
}
