function Get-YamlMergeNodeTag {
    <#
        .SYNOPSIS
        Gets the effective tag used for YAML merge compatibility.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node
    )

    $effective = Get-YamlMergeNode -Node $Node
    $value = if ($effective.Kind -eq 'Scalar') {
        (Resolve-YamlScalar -Node $effective).Value
    } else {
        $null
    }
    Get-YamlEffectiveTag -Node $effective -Value $value
}
