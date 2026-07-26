function Move-YamlCursor {
    <#
        .SYNOPSIS
        Advances a mutable parser cursor.

        .DESCRIPTION
        Moves through normalized reader text while keeping index, line, and column
        coordinates synchronized. Scanner helpers depend on this cursor state to
        produce accurate marks after skipping trivia or consuming tokens.

        .EXAMPLE
        Move-YamlCursor -Cursor $cursor -Context $context -Count 3

        Advances the cursor by up to three characters and updates line and column positions.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Advances an in-memory parser cursor.'
    )]
    [CmdletBinding()]
    param (
        # The mutable parser position to advance through the YAML stream.
        [Parameter(Mandatory)]
        [pscustomobject] $Cursor,

        # The reader context that provides the normalized text and stream length.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # The number of characters to consume without moving past the stream end.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $Count = 1
    )

    for ($step = 0; $step -lt $Count -and $Cursor.Index -lt $Context.Text.Length; $step++) {
        $character = $Context.Text[$Cursor.Index]
        $Cursor.Index++
        if ($character -eq "`n") {
            $Cursor.Line++
            $Cursor.Column = 0
        } else {
            $Cursor.Column++
        }
    }
}
