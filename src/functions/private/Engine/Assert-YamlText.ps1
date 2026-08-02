function Assert-YamlText {
    <#
        .SYNOPSIS
        Validates YAML input characters before parsing.

        .DESCRIPTION
        Scans the stream for characters outside the YAML c-printable set or
        unpaired UTF-16 surrogates and throws a classified YAML exception that
        points at the offending line and column. Returns nothing when the text is
        valid.

        .EXAMPLE
        Assert-YamlText -Yaml 'name: Ada'

        Returns nothing because every character is c-printable.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    param (
        # The raw YAML stream to validate before tokenization; may be empty.
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
