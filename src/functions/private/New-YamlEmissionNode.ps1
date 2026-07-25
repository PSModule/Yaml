function New-YamlEmissionNode {
    <#
        .SYNOPSIS
        Creates an internal YAML emission node.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory representation node without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
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
