function Get-YamlTagPresentationLimit {
    <#
        .SYNOPSIS
        Gets an allocation-safe presentation bound for a decoded tag limit.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [switch] $Token
    )

    # One UTF-16 code unit can require three UTF-8 bytes, each written as %XX.
    $limit = 9L * $Context.MaxTagLength
    if ($Token) {
        $maximumHandleLength = 0
        foreach ($handle in $Context.TagHandles.Keys) {
            $maximumHandleLength = [Math]::Max($maximumHandleLength, $handle.Length)
        }
        $limit += $maximumHandleLength + 3L
    }

    [int] [Math]::Min($limit, [int]::MaxValue)
}
