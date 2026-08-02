function Test-YamlReservedDirective {
    <#
        .SYNOPSIS
        Tests the YAML reserved-directive name and parameter productions.

        .DESCRIPTION
        Checks that a percent-led reserved directive has a non-empty name and only
        separated tokens before any comment. This lets the scanner tolerate
        application-specific directives while rejecting malformed directive lines.

        .EXAMPLE
        Test-YamlReservedDirective -Directive '%FOO one two # comment'

        Returns true because the directive has a name and separated parameters.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # Supplies the complete directive line so comments and token separation can be checked.
        [Parameter(Mandatory)]
        [string] $Directive
    )

    if ($Directive.Length -lt 2 -or -not $Directive[0].Equals([char] '%')) {
        return $false
    }

    $comment = Find-YamlCommentStart -Text $Directive
    $contentEnd = if ($comment -ge 0) { $comment } else { $Directive.Length }
    $body = $Directive.Substring(1, $contentEnd - 1).TrimEnd(' ', "`t")
    if ($body.Length -eq 0 -or (Test-YamlWhiteSpace -Character $body[0])) {
        return $false
    }

    $index = 0
    while ($index -lt $body.Length) {
        $tokenStart = $index
        while ($index -lt $body.Length -and
            -not (Test-YamlWhiteSpace -Character $body[$index])) {
            $index++
        }
        if ($index -eq $tokenStart) {
            return $false
        }
        while ($index -lt $body.Length -and
            (Test-YamlWhiteSpace -Character $body[$index])) {
            $index++
        }
    }
    return $true
}
