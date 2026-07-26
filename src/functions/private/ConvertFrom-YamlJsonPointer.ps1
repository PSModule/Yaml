function ConvertFrom-YamlJsonPointer {
    <#
        .SYNOPSIS
        Parses and strictly decodes one RFC 6901 JSON Pointer.

        .DESCRIPTION
        Validates that a removal path is an RFC 6901 JSON Pointer and decodes
        each token's tilde escapes. Strict decoding prevents ambiguous or
        non-standard paths from selecting unintended YAML graph edges.

        .EXAMPLE
        ConvertFrom-YamlJsonPointer -Pointer '/metadata/internal~1id' -State $state

        Returns a boxed token array containing metadata and internal/id.

        .LINK
        https://psmodule.io/Yaml/Functions/Remove-YamlEntry/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # The raw removal path must be decoded once so later graph resolution
        # uses canonical tokens.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Pointer,

        # The work state charges parsing by pointer length to keep path
        # processing bounded.
        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    $workCount = [Math]::Max(1, $Pointer.Length)
    Add-YamlRemovalWork -State $State -Count $workCount -Operation 'pointer parsing'
    if ($Pointer.Length -eq 0) {
        return New-YamlValueBox -Value ([string[]]::new(0))
    }
    if ($Pointer[0] -cne '/') {
        throw (New-YamlRemovalException -ErrorId 'YamlRemovalInvalidPointer' -Message (
                'A YAML removal path must be empty or start with a slash as required by RFC 6901.'
            ))
    }

    $rawTokens = $Pointer.Substring(1).Split(
        [char[]] @('/'),
        [System.StringSplitOptions]::None
    )
    $tokens = [System.Collections.Generic.List[string]]::new()
    foreach ($rawToken in $rawTokens) {
        $decoded = [System.Text.StringBuilder]::new()
        for ($index = 0; $index -lt $rawToken.Length; $index++) {
            $character = $rawToken[$index]
            if ($character -cne '~') {
                [void] $decoded.Append($character)
                continue
            }

            if ($index + 1 -ge $rawToken.Length) {
                throw (New-YamlRemovalException `
                        -ErrorId 'YamlRemovalInvalidPointerEscape' -Message (
                        'A YAML removal path contains an incomplete JSON Pointer tilde escape.'
                    ))
            }
            $escaped = $rawToken[$index + 1]
            if ($escaped -ceq '0') {
                [void] $decoded.Append('~')
            } elseif ($escaped -ceq '1') {
                [void] $decoded.Append('/')
            } else {
                throw (New-YamlRemovalException `
                        -ErrorId 'YamlRemovalInvalidPointerEscape' -Message (
                        "A YAML removal path contains invalid JSON Pointer escape '~$escaped'; " +
                        "only '~0' and '~1' are valid."
                    ))
            }
            $index++
        }
        $tokens.Add($decoded.ToString())
    }

    return New-YamlValueBox -Value ([string[]] $tokens.ToArray())
}
