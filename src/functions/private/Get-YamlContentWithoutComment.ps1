function Get-YamlContentWithoutComment {
    <#
        .SYNOPSIS
        Removes a separated comment from non-flow scalar text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

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
