function Skip-YamlFlowTrivia {
    <#
        .SYNOPSIS
        Skips separation whitespace and comments inside flow content.
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
        [pscustomobject] $Context
    )

    while ($Cursor.Index -lt $Context.Text.Length) {
        $character = $Context.Text[$Cursor.Index]
        if ($character -eq ' ' -or $character -eq "`t") {
            Move-YamlCursor -Cursor $Cursor -Context $Context
            continue
        }
        if ($character -eq '#') {
            $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
            if ($Cursor.Index -gt 0 -and
                $Context.Text[$Cursor.Index - 1] -notin @(' ', "`t", "`n")) {
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidComment' -Message (
                        'A YAML comment must be separated from preceding content.'
                    ))
            }
            $commentEnd = $Context.Text.IndexOf(
                "`n",
                $Cursor.Index,
                [System.StringComparison]::Ordinal
            )
            if ($commentEnd -lt 0) {
                $commentEnd = $Context.Text.Length
            }
            Assert-YamlNoByteOrderMark `
                -Text $Context.Text.Substring($Cursor.Index, $commentEnd - $Cursor.Index) `
                -Mark $mark
            while ($Cursor.Index -lt $Context.Text.Length -and $Context.Text[$Cursor.Index] -ne "`n") {
                Move-YamlCursor -Cursor $Cursor -Context $Context
            }
            continue
        }
        if ($character -ne "`n") {
            break
        }

        Move-YamlCursor -Cursor $Cursor -Context $Context
        while ($Cursor.Index -lt $Context.Text.Length) {
            $lineStart = $Cursor.Index
            $spaceIndent = 0
            while ($Cursor.Index -lt $Context.Text.Length -and
                $Context.Text[$Cursor.Index] -eq ' ') {
                $spaceIndent++
                Move-YamlCursor -Cursor $Cursor -Context $Context
            }
            while ($Cursor.Index -lt $Context.Text.Length -and
                $Context.Text[$Cursor.Index] -eq "`t") {
                Move-YamlCursor -Cursor $Cursor -Context $Context
            }
            if ($Cursor.Index -ge $Context.Text.Length) {
                return
            }
            if ($Context.Text[$Cursor.Index] -eq '#') {
                $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                $commentEnd = $Context.Text.IndexOf(
                    "`n",
                    $Cursor.Index,
                    [System.StringComparison]::Ordinal
                )
                if ($commentEnd -lt 0) {
                    $commentEnd = $Context.Text.Length
                }
                Assert-YamlNoByteOrderMark `
                    -Text $Context.Text.Substring($Cursor.Index, $commentEnd - $Cursor.Index) `
                    -Mark $mark
                while ($Cursor.Index -lt $Context.Text.Length -and $Context.Text[$Cursor.Index] -ne "`n") {
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                }
                if ($Cursor.Index -lt $Context.Text.Length) {
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                    continue
                }
                return
            }
            if ($Context.Text[$Cursor.Index] -eq "`n") {
                Move-YamlCursor -Cursor $Cursor -Context $Context
                continue
            }

            $indent = $Cursor.Index - $lineStart
            if ($indent -eq 0 -and $Cursor.Index + 3 -le $Context.Text.Length) {
                $marker = $Context.Text.Substring($Cursor.Index, 3)
                if ($marker -cin @('---', '...') -and
                    ($Cursor.Index + 3 -eq $Context.Text.Length -or
                    (Test-YamlWhiteSpace -Character $Context.Text[$Cursor.Index + 3]) -or
                    $Context.Text[$Cursor.Index + 3] -ceq "`n")) {
                    $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column 0
                    throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidFlowCollection' -Message (
                            'A document marker cannot occur inside a flow collection.'
                        ))
                }
            }
            $isClosing = $Context.Text[$Cursor.Index] -eq ']' -or $Context.Text[$Cursor.Index] -eq '}'
            if ((-not $isClosing -and $spaceIndent -le $Cursor.ParentIndent) -or
                ($isClosing -and $spaceIndent -lt $Cursor.ParentIndent)) {
                $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidFlowIndentation' -Message (
                        'Continuation lines in a flow collection must be indented beyond the surrounding block context.'
                    ))
            }
            break
        }
    }
}
