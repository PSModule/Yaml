function New-YamlNode {
    <#
        .SYNOPSIS
        Creates an internal YAML representation node.

        .DESCRIPTION
        Builds the common node record used for scalar, sequence, mapping, and alias
        syntax tokens. The parser fills these default fields as it reads the YAML
        stream and later composes the representation graph.

        .EXAMPLE
        New-YamlNode -Id 1 -Kind Scalar -Start $mark -End $mark

        Returns a scalar node initialized with source marks and empty parser metadata.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory representation node without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The stable identifier used to track node identity, anchors, and aliases.
        [Parameter(Mandatory)]
        [int] $Id,

        # The YAML node kind that determines which parser fields will be populated.
        [Parameter(Mandatory)]
        [ValidateSet('Alias', 'Mapping', 'Scalar', 'Sequence')]
        [string] $Kind,

        # The source location where this node begins for diagnostics.
        [Parameter(Mandatory)]
        [pscustomobject] $Start,

        # The source location where this node ends for diagnostics.
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
