function ConvertFrom-YamlTagUriEscape {
    <#
        .SYNOPSIS
        Decodes YAML tag URI %xx escapes as UTF-8.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [pscustomobject] $Mark,

        [Parameter(Mandatory)]
        [string] $Token
    )

    $builder = [System.Text.StringBuilder]::new()
    $escapedBytes = [System.Collections.Generic.List[byte]]::new()
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)

    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($character -ne '%') {
            if ($escapedBytes.Count -gt 0) {
                try {
                    [void] $builder.Append($utf8.GetString($escapedBytes.ToArray()))
                } catch [System.Text.DecoderFallbackException] {
                    throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                            "The tag token '$Token' contains an invalid UTF-8 escape sequence."
                        ))
                }
                $escapedBytes.Clear()
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
            [void] $builder.Append($utf8.GetString($escapedBytes.ToArray()))
        } catch [System.Text.DecoderFallbackException] {
            throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                    "The tag token '$Token' contains an invalid UTF-8 escape sequence."
                ))
        }
    }

    $builder.ToString()
}
