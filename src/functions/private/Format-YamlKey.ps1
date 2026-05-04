function Format-YamlKey {
    <#
        .SYNOPSIS
        Renders a mapping key as a YAML scalar, quoting when necessary.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [object] $Key
    )

    $text = [string] $Key
    if ([string]::IsNullOrEmpty($text)) { return "''" }
    if (Test-YamlPlainSafe -Text $text -ForKey) {
        return $text
    }
    if ($text -notmatch "'") { return "'$text'" }
    return Format-YamlDoubleQuoted -Text $text
}
