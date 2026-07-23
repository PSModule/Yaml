function ConvertFrom-YamlByteOrderMark {
    <#
        .SYNOPSIS
        Consumes byte order marks at YAML stream and explicit document boundaries.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    if ($Text.IndexOf([char] 0xFEFF) -lt 0) {
        return $Text
    }

    $builder = [System.Text.StringBuilder]::new($Text.Length)
    for ($index = 0; $index -lt $Text.Length; $index++) {
        if ($Text[$index] -cne [char] 0xFEFF) {
            [void] $builder.Append($Text[$index])
            continue
        }

        $atStreamStart = $index -eq 0
        $atLineStart = $index -gt 0 -and $Text[$index - 1] -ceq "`n"
        $beforeDocumentPrefix = $atLineStart -and (
            Test-YamlDocumentPrefix -Text $Text -Index ($index + 1)
        )

        if ($atStreamStart -or $beforeDocumentPrefix) {
            continue
        }

        $before = $Text.Substring(0, $index)
        $line = ([regex]::Matches($before, "`n")).Count
        $lastBreak = $before.LastIndexOf("`n", [System.StringComparison]::Ordinal)
        $column = if ($lastBreak -lt 0) { $before.Length } else { $before.Length - $lastBreak - 1 }
        $mark = New-YamlMark -Index $index -Line $line -Column $column
        throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidByteOrderMark' -Message (
                'A YAML byte order mark is only allowed at the start of the stream or a document prefix.'
            ))
    }

    return $builder.ToString()
}
