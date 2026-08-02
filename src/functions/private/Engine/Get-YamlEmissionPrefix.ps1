function Get-YamlEmissionPrefix {
    <#
        .SYNOPSIS
        Gets anchor and standard-tag presentation for one emission node.

        .DESCRIPTION
        Builds the textual anchor and tag prefix that appears before a node value. Centralizing this
        keeps anchors, explicit standard tags, and unknown tag markers emitted consistently.

        .EXAMPLE
        Get-YamlEmissionPrefix -Node $node

        Returns the anchor and tag prefix text that should be written before the node value.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The normalized emission node provides the final anchor and tag metadata to present.
        [Parameter(Mandatory)]
        [pscustomobject] $Node
    )

    $parts = [System.Collections.Generic.List[string]]::new()
    if (-not [string]::IsNullOrEmpty($Node.Anchor)) {
        $parts.Add("&$($Node.Anchor)")
    }
    if (-not [string]::IsNullOrEmpty($Node.Tag)) {
        $parts.Add((ConvertTo-YamlTagText -Tag $Node.Tag))
    } elseif ($Node.HasUnknownTag) {
        $parts.Add('!')
    }
    return $parts -join ' '
}
