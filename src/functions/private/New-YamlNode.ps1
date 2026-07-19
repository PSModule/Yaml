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
        [YamlDotNet.Core.Mark] $Start,

        [Parameter(Mandatory)]
        [YamlDotNet.Core.Mark] $End
    )

    $node = [pscustomobject]@{
        PSTypeName       = 'PSModule.Yaml.InternalNode'
        Id               = $Id
        Kind             = $Kind
        Tag              = ''
        Anchor           = ''
        Value            = $null
        Style            = $null
        IsPlainImplicit  = $false
        IsQuotedImplicit = $false
        Items            = [System.Collections.Generic.List[object]]::new()
        Entries          = [System.Collections.Generic.List[object]]::new()
        Target           = $null
        Start            = $Start
        End              = $End
    }
    Write-Output -InputObject $node -NoEnumerate
}
