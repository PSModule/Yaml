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

    $comment = [regex]::Match($Text, '(?<!\S)#')
    if ($comment.Success) {
        return $Text.Substring(0, $comment.Index).TrimEnd()
    }
    return $Text.TrimEnd()
}
