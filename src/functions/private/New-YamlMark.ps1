function New-YamlMark {
    <#
        .SYNOPSIS
        Creates an internal source location.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory source location.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [int] $Index,

        [Parameter(Mandatory)]
        [int] $Line,

        [Parameter(Mandatory)]
        [int] $Column
    )

    [pscustomobject]@{
        Index  = $Index
        Line   = $Line
        Column = $Column
    }
}
