function Get-YamlEffectiveTag {
    <#
        .SYNOPSIS
        Gets the effective representation tag for a YAML node.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value
    )

    if (-not [string]::IsNullOrEmpty($Node.Tag) -and
        -not $Node.Tag.Equals('!', [System.StringComparison]::Ordinal)) {
        return $Node.Tag
    }
    if ($Node.Kind.Equals('Sequence', [System.StringComparison]::Ordinal)) {
        return 'tag:yaml.org,2002:seq'
    }
    if ($Node.Kind.Equals('Mapping', [System.StringComparison]::Ordinal)) {
        return 'tag:yaml.org,2002:map'
    }
    if ($Node.Tag.Equals('!', [System.StringComparison]::Ordinal)) {
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
