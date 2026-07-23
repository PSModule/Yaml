function New-YamlReaderContext {
    <#
        .SYNOPSIS
        Validates Unicode input and creates the parser reader state.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory reader context.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Yaml,

        [Parameter(Mandatory)]
        [int] $Depth,

        [Parameter(Mandatory)]
        [int] $MaxNodes,

        [Parameter(Mandatory)]
        [int] $MaxAliases,

        [Parameter(Mandatory)]
        [int] $MaxScalarLength,

        [Parameter(Mandatory)]
        [int] $MaxTagLength,

        [Parameter(Mandatory)]
        [int] $MaxTotalTagLength,

        [Parameter(Mandatory)]
        [int] $MaxNumericLength
    )

    $text = $Yaml.Replace("`r`n", "`n").Replace("`r", "`n")
    $text = ConvertFrom-YamlByteOrderMark -Text $text
    Assert-YamlText -Yaml $text
    $lines = [System.Text.RegularExpressions.Regex]::Split($text, "`n")
    $lineStarts = [int[]]::new($lines.Count)
    $offset = 0
    for ($line = 0; $line -lt $lines.Count; $line++) {
        $lineStarts[$line] = $offset
        $offset += $lines[$line].Length + 1
    }

    [pscustomobject]@{
        PSTypeName        = 'PSModule.Yaml.ReaderContext'
        Text              = $text
        Lines             = $lines
        LineStarts        = $lineStarts
        LineIndex         = 0
        NextId            = 1
        NodeCount         = 0
        AliasCount        = 0
        TotalTagLength    = 0
        MaxDepth          = $Depth
        MaxNodes          = $MaxNodes
        MaxAliases        = $MaxAliases
        MaxScalarLength   = $MaxScalarLength
        MaxTagLength      = $MaxTagLength
        MaxTotalTagLength = $MaxTotalTagLength
        MaxNumericLength  = $MaxNumericLength
        Anchors           = $null
        TagHandles        = $null
    }
}
