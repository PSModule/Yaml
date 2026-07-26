function New-YamlEmissionNode {
    <#
        .SYNOPSIS
        Creates an internal YAML emission node.

        .DESCRIPTION
        Initializes the mutable internal node object used by the serializer and
        emitter. It supplies consistent defaults for tags, scalar style,
        collection containers, references, and anchors before callers add content.

        .EXAMPLE
        New-YamlEmissionNode -Kind Mapping

        Returns an empty mapping emission node ready to receive entries.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertTo-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory representation node without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # Selects the node shape so downstream writer code uses the right container.
        [Parameter(Mandatory)]
        [ValidateSet('Mapping', 'Scalar', 'Sequence')]
        [string] $Kind
    )

    $node = [pscustomobject]@{
        PSTypeName    = 'PSModule.Yaml.EmissionNode'
        Kind          = $Kind
        Tag           = ''
        HasUnknownTag = $false
        Value         = ''
        Style         = 'Plain'
        Items         = [System.Collections.Generic.List[object]]::new()
        Entries       = [System.Collections.Generic.List[object]]::new()
        ReferenceId   = [long] 0
        Anchor        = ''
    }
    Write-Output -InputObject $node -NoEnumerate
}
