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
        $prefix = 'tag:yaml.org,2002:'
        if ($Node.Tag.StartsWith($prefix, [System.StringComparison]::Ordinal)) {
            $parts.Add("!!$($Node.Tag.Substring($prefix.Length))")
        } else {
            $parts.Add("!<$($Node.Tag)>")
        }
    }
    return $parts -join ' '
}
