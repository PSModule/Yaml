function Get-YamlContentWithoutComment {
    <#
        .SYNOPSIS
        Removes a separated comment from non-flow scalar text.

        .DESCRIPTION
        Finds a separated comment in non-flow scalar text, validates that no
        forbidden BOM appears in the comment slice, and trims trailing separation.
        The scanner uses the stripped content while keeping source diagnostics exact.

        .EXAMPLE
        Get-YamlContentWithoutComment -Text 'name # comment' -Mark $mark

        Returns name after removing the separated comment and trailing space.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # Supplies the raw non-flow scalar text that may contain a separated comment.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        # Anchors comment diagnostics to the scalar's original source position.
        [Parameter(Mandatory)]
        [pscustomobject] $Mark
    )

    $comment = Find-YamlCommentStart -Text $Text
    if ($comment -ge 0) {
        $commentMark = New-YamlMark -Index ($Mark.Index + $comment) -Line $Mark.Line `
            -Column ($Mark.Column + $comment)
        Assert-YamlNoByteOrderMark -Text $Text.Substring($comment) -Mark $commentMark
        return $Text.Substring(0, $comment).TrimEnd(' ', "`t")
    }
    return $Text.TrimEnd(' ', "`t")
}
