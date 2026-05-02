function Format-YamlString {
    <#
        .SYNOPSIS
        Renders a string as a YAML scalar, quoting and escaping as needed.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    if ($Text.Length -eq 0) { return "''" }

    # Always double-quote strings that contain control characters or quotes that need escaping.
    $needsDoubleQuote = $false
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int] $ch
        if ($code -lt 0x20 -or $code -eq 0x7F) {
            $needsDoubleQuote = $true
            break
        }
    }

    if ($needsDoubleQuote) {
        return Format-YamlDoubleQuoted -Text $Text
    }

    if (Test-YamlPlainSafe -Text $Text) {
        return $Text
    }

    # Prefer single quotes when the text doesn't contain a single quote; otherwise double-quote.
    if ($Text -notmatch "'") {
        return "'$Text'"
    }

    return Format-YamlDoubleQuoted -Text $Text
}
