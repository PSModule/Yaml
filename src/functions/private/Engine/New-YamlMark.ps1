function New-YamlMark {
    <#
        .SYNOPSIS
        Creates an internal source location.

        .DESCRIPTION
        Captures a zero-based character index, line, and column from the reader
        cursor. Parser errors and nodes use these marks so ConvertFrom-Yaml can
        report precise YAML source locations.

        .EXAMPLE
        New-YamlMark -Index 12 -Line 0 -Column 12

        Returns a source mark pointing at the thirteenth character on the first line.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory source location.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The zero-based character offset in the normalized YAML stream.
        [Parameter(Mandatory)]
        [int] $Index,

        # The zero-based line number used for source diagnostics.
        [Parameter(Mandatory)]
        [int] $Line,

        # The zero-based column number used for source diagnostics.
        [Parameter(Mandatory)]
        [int] $Column
    )

    [pscustomobject]@{
        Index  = $Index
        Line   = $Line
        Column = $Column
    }
}
