function Assert-YamlText {
    <#
        .SYNOPSIS
        Validates YAML input characters before parsing.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Yaml
    )

    $invalid = [regex]::Match(
        $Yaml,
        '[^\x09\x0A\x0D\x20-\x7E\x85\xA0-\uD7FF\uD800-\uDFFF\uE000-\uFFFD]|' +
        '[\uD800-\uDBFF](?![\uDC00-\uDFFF])|(?<![\uD800-\uDBFF])[\uDC00-\uDFFF]',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if ($invalid.Success) {
        $before = $Yaml.Substring(0, $invalid.Index)
        $line = ([regex]::Matches($before, "`n")).Count
        $lastBreak = $before.LastIndexOf("`n", [System.StringComparison]::Ordinal)
        $column = if ($lastBreak -lt 0) {
            $before.Length
        } else {
            $before.Length - $lastBreak - 1
        }
        $mark = New-YamlMark -Index $invalid.Index -Line $line -Column $column
        throw (New-YamlException -Start $mark -End $mark `
                -ErrorId 'YamlInvalidCharacter' -Message (
                'The YAML stream contains a character outside the YAML c-printable set or an unpaired surrogate.'
            ))
    }
}
