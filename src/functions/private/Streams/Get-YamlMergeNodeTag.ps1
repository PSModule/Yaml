function Get-YamlMergeNodeTag {
    <#
        .SYNOPSIS
        Gets the effective tag used for YAML merge compatibility.

        .DESCRIPTION
        Resolves aliases and returns the effective YAML tag used to decide merge
        compatibility. Scalars are resolved first so implicit tags reflect
        constructed values rather than presentation text.

        .EXAMPLE
        Get-YamlMergeNodeTag -Node $candidateNode

        Returns the effective tag, such as tag:yaml.org,2002:str, for merge
        comparisons.

        .LINK
        https://psmodule.io/Yaml/Functions/Streams/Merge-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The representation node whose effective compatibility tag is needed.
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
