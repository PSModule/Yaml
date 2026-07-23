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
        [string] $Text
    )

    $comment = Find-YamlCommentStart -Text $Text
    if ($comment -ge 0) {
        return $Text.Substring(0, $comment).TrimEnd(' ', "`t")
    }
    return $Text.TrimEnd(' ', "`t")
}
