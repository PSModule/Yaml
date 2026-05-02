function Get-YamlMappingPair {
    <#
        .SYNOPSIS
        Returns a list of [pscustomobject]@{ Key; Value } for a dictionary or PSObject.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '',
        Justification = 'Comma-unary operator preserves List type; PSScriptAnalyzer misdetects as Object[].')]
    [CmdletBinding()]
    [OutputType([System.Collections.Generic.List[pscustomobject]])]
    param(
        [Parameter(Mandatory)]
        [object] $Value
    )

    $pairs = [System.Collections.Generic.List[pscustomobject]]::new()
    $raw = if ($Value -is [psobject] -and $null -ne $Value.PSObject -and $null -ne $Value.PSObject.BaseObject) {
        $Value.PSObject.BaseObject
    } else {
        $Value
    }

    if ($raw -is [System.Collections.IDictionary]) {
        foreach ($key in $raw.Keys) {
            $pairs.Add([pscustomobject]@{ Key = $key; Value = $raw[$key] })
        }
        return , $pairs
    }

    if ($Value -is [psobject]) {
        foreach ($prop in $Value.PSObject.Properties) {
            $pairs.Add([pscustomobject]@{ Key = $prop.Name; Value = $prop.Value })
        }
    }

    return , $pairs
}
