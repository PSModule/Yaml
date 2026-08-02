function Get-YamlTagPresentationLimit {
    <#
        .SYNOPSIS
        Gets an allocation-safe presentation bound for a decoded tag limit.

        .DESCRIPTION
        Calculates the worst-case escaped tag text length from the decoded tag limit and known
        handles. The emitter uses this bound to reject oversized tag presentations without
        allocating unbounded strings.

        .EXAMPLE
        Get-YamlTagPresentationLimit -Context $context -Token

        Returns the maximum escaped tag-token presentation length allowed for the current context.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        # The serialization context supplies tag length limits and handles used in the bound.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # Token mode includes handle and delimiter overhead when checking a full tag token.
        [Parameter()]
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
