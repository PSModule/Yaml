function Expand-YamlDoubleQuoted {
    <#
        .SYNOPSIS
        Expands escape sequences inside a double-quoted YAML scalar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ($c -eq '\' -and $i + 1 -lt $Text.Length) {
            $next = $Text[$i + 1]
            $expanded = $true
            switch ($next) {
                'n' { $null = $sb.Append("`n") }
                't' { $null = $sb.Append("`t") }
                'r' { $null = $sb.Append("`r") }
                '"' { $null = $sb.Append('"') }
                '\' { $null = $sb.Append('\') }
                '0' { $null = $sb.Append([char]0) }
                'x' {
                    if ($i + 3 -lt $Text.Length) {
                        $hex = $Text.Substring($i + 2, 2)
                        $code = 0
                        if ([int]::TryParse($hex, [System.Globalization.NumberStyles]::HexNumber, $null, [ref]$code)) {
                            $null = $sb.Append([char]$code)
                            $i += 4
                            continue
                        }
                    }
                    $expanded = $false
                }
                default { $expanded = $false }
            }

            if ($expanded) {
                $i += 2
                continue
            }
        }
        $null = $sb.Append($c)
        $i++
    }
    return $sb.ToString()
}
