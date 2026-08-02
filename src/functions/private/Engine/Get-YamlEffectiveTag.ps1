function Get-YamlEffectiveTag {
    <#
        .SYNOPSIS
        Gets the effective representation tag for a YAML node.

        .DESCRIPTION
        Returns the explicit node tag when one is present, otherwise derives the
        standard YAML tag from node kind and resolved value. Format, merge, and
        projection code use this to compare representation semantics consistently.

        .EXAMPLE
        Get-YamlEffectiveTag -Node $node -Value $resolved.Value

        Returns the standard YAML tag that represents the node's effective value.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # Provides the representation node whose explicit tag or kind takes precedence.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # Supplies the resolved scalar value so implicit scalar tags can be derived.
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value
    )

    if (-not [string]::IsNullOrEmpty($Node.Tag)) {
        return $Node.Tag
    }
    if ($Node.Kind.Equals('Sequence', [System.StringComparison]::Ordinal)) {
        return 'tag:yaml.org,2002:seq'
    }
    if ($Node.Kind.Equals('Mapping', [System.StringComparison]::Ordinal)) {
        return 'tag:yaml.org,2002:map'
    }
    if ($Node.HasUnknownTag) {
        return 'tag:yaml.org,2002:str'
    }

    if ($null -eq $Value) {
        return 'tag:yaml.org,2002:null'
    }
    if ($Value -is [string]) {
        return 'tag:yaml.org,2002:str'
    }
    if ($Value -is [bool]) {
        return 'tag:yaml.org,2002:bool'
    }
    if ($Value -is [byte[]]) {
        return 'tag:yaml.org,2002:binary'
    }
    if ($Value -is [datetime] -or $Value -is [datetimeoffset]) {
        return 'tag:yaml.org,2002:timestamp'
    }
    if ($Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) {
        return 'tag:yaml.org,2002:float'
    }
    return 'tag:yaml.org,2002:int'
}
