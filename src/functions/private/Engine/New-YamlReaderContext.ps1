function New-YamlReaderContext {
    <#
        .SYNOPSIS
        Validates Unicode input and creates the parser reader state.

        .DESCRIPTION
        Normalizes line endings, validates the YAML stream as acceptable parser input,
        and prepares line-offset metadata and resource counters. ConvertFrom-Yaml uses
        this context as shared state while scanner and reader helpers build nodes.

        .EXAMPLE
        New-YamlReaderContext -Yaml $yaml -Depth 100 -MaxNodes 100000 -MaxAliases 1000 -MaxScalarLength 1048576 `
            -MaxTagLength 1024 -MaxTotalTagLength 65536 -MaxNumericLength 4096

        Returns a reader context containing normalized text, line starts, parser limits, and initial counters.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory reader context.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The YAML stream to normalize and validate before parser scanning begins.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Yaml,

        # The maximum nesting depth enforced while parser readers allocate nodes.
        [Parameter(Mandatory)]
        [int] $Depth,

        # The maximum number of representation nodes allowed for the stream.
        [Parameter(Mandatory)]
        [int] $MaxNodes,

        # The maximum number of aliases allowed during composition.
        [Parameter(Mandatory)]
        [int] $MaxAliases,

        # The maximum decoded scalar length the scanner and readers may accept.
        [Parameter(Mandatory)]
        [int] $MaxScalarLength,

        # The maximum expanded tag length allowed for any single node.
        [Parameter(Mandatory)]
        [int] $MaxTagLength,

        # The cumulative expanded tag budget shared across the parsed stream.
        [Parameter(Mandatory)]
        [int] $MaxTotalTagLength,

        # The maximum numeric scalar length passed into constructed syntax nodes.
        [Parameter(Mandatory)]
        [int] $MaxNumericLength
    )

    $text = $Yaml.Replace("`r`n", "`n").Replace("`r", "`n")
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
