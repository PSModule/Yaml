function Move-YamlCursor {
    <#
        .SYNOPSIS
        Advances a mutable parser cursor.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Advances an in-memory parser cursor.'
    )]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Cursor,

        [Parameter(Mandatory)]
        [pscustomobject] $Context,

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
