function Assert-YamlNoByteOrderMark {
    <#
        .SYNOPSIS
        Rejects a raw byte order mark outside a quoted scalar or document prefix.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [pscustomobject] $Mark
    )

    if ($Text.IndexOf([char] 0xFEFF) -ge 0) {
        throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidByteOrderMark' -Message (
                'A raw YAML byte order mark is only allowed in a quoted scalar or document prefix.'
            ))
    }
}
