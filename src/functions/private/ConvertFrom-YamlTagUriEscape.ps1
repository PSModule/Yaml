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

    function Get-YamlHexNibble {
        param ([char] $Character)
        if ($Character -notmatch '^[0-9A-Fa-f]$') {
            return -1
        }
        [System.Convert]::ToInt32([string] $Character, 16)
    }

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
        $high = Get-YamlHexNibble -Character $Text[$index + 1]
        $low = Get-YamlHexNibble -Character $Text[$index + 2]
        if ($high -lt 0 -or $low -lt 0) {
            throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                    "The tag token '$Token' contains a malformed percent escape."
                ))
        }
        $escapedBytes.Add([byte](($high * 16) + $low))
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
