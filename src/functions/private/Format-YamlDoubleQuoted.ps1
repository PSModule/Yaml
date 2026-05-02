function Format-YamlDoubleQuoted {
    <#
        .SYNOPSIS
        Wraps a string in double quotes, escaping special characters per YAML rules.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $sb = [System.Text.StringBuilder]::new()
    $null = $sb.Append('"')
    foreach ($ch in $Text.ToCharArray()) {
        $code = [int] $ch
        if ($ch -eq '\') { $null = $sb.Append('\\'); continue }
        if ($ch -eq '"') { $null = $sb.Append('\"'); continue }
        if ($ch -eq "`n") { $null = $sb.Append('\n'); continue }
        if ($ch -eq "`t") { $null = $sb.Append('\t'); continue }
        if ($ch -eq "`r") { $null = $sb.Append('\r'); continue }
        if ($code -lt 0x20 -or $code -eq 0x7F) {
            $null = $sb.AppendFormat('\x{0:x2}', $code)
            continue
        }
        $null = $sb.Append($ch)
    }
    $null = $sb.Append('"')
    return $sb.ToString()
}
