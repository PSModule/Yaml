function ConvertFrom-YamlTagUriText {
    <#
        .SYNOPSIS
        Decodes percent-encoded UTF-8 octets in YAML tag URI text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $builder = [System.Text.StringBuilder]::new($Text.Length)
    $bytes = [System.Collections.Generic.List[byte]]::new()
    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $index = 0

    while ($index -lt $Text.Length) {
        if ($Text[$index] -ne '%') {
            [void] $builder.Append($Text[$index])
            $index++
            continue
        }

        $bytes.Clear()
        while ($index -lt $Text.Length -and $Text[$index] -eq '%') {
            if ($index + 2 -ge $Text.Length -or
                $Text[$index + 1] -notmatch '^[0-9A-Fa-f]$' -or
                $Text[$index + 2] -notmatch '^[0-9A-Fa-f]$') {
                throw [System.FormatException]::new(
                    "The tag URI contains an incomplete or malformed percent escape at index $index."
                )
            }

            $bytes.Add([System.Convert]::ToByte($Text.Substring($index + 1, 2), 16))
            $index += 3
        }

        [void] $builder.Append($utf8.GetString($bytes.ToArray()))
    }

    $builder.ToString()
}
