function New-YamlNode {
    <#
        .SYNOPSIS
        Creates an internal YAML representation node.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory representation node without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [int] $Id,

        [Parameter(Mandatory)]
        [ValidateSet('Alias', 'Mapping', 'Scalar', 'Sequence')]
        [string] $Kind,

        [Parameter(Mandatory)]
        [pscustomobject] $Start,

        [Parameter(Mandatory)]
        [pscustomobject] $End
    )

    $node = [pscustomobject]@{
        PSTypeName       = 'PSModule.Yaml.InternalNode'
        Id               = $Id
        Kind             = $Kind
        Tag              = ''
        HasUnknownTag    = $false
        Anchor           = ''
        Value            = $null
        Style            = 'Plain'
        IsPlainImplicit  = $false
        IsQuotedImplicit = $false
        ResolutionState  = 0
        ResolvedValue    = $null
        MaxNumericLength = 4096
        Items            = [System.Collections.Generic.List[object]]::new()
        Entries          = [System.Collections.Generic.List[object]]::new()
        Target           = $null
        Start            = $Start
        End              = $End
    }
    Write-Output -InputObject $node -NoEnumerate
}
