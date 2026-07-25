function Get-YamlEmissionPrefix {
    <#
        .SYNOPSIS
        Gets anchor and standard-tag presentation for one emission node.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
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
