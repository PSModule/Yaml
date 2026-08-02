function Assert-YamlNoByteOrderMark {
    <#
        .SYNOPSIS
        Rejects a raw byte order mark outside a quoted scalar or document prefix.

        .DESCRIPTION
        Searches a YAML text segment for U+FEFF after the parser has determined
        the position is not a valid document prefix or quoted-scalar character.
        It throws a location-aware YAML error so invisible byte order marks do
        not pass through plain content.

        .EXAMPLE
        Assert-YamlNoByteOrderMark -Text 'name: Ada' -Mark (New-YamlMark -Index 0 -Line 0 -Column 0)

        Returns nothing because the text contains no byte order mark.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    param (
        # The text segment to scan for an illegal raw byte order mark.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        # The parser mark to report if the segment contains U+FEFF.
        [Parameter(Mandatory)]
        [pscustomobject] $Mark
    )

    if ($Text.IndexOf([char] 0xFEFF) -ge 0) {
        throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidByteOrderMark' -Message (
                'A raw YAML byte order mark is only allowed in a quoted scalar or document prefix.'
            ))
    }
}
