function Get-YamlMergeNode {
    <#
        .SYNOPSIS
        Resolves aliases to their effective YAML representation node.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node
    )

    $effective = $Node
    while ($effective.Kind -eq 'Alias') {
        $effective = $effective.Target
    }
    Write-Output -InputObject $effective -NoEnumerate
}
