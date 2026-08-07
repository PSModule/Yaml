function Test-YamlDocumentSurface {
    <#
        .SYNOPSIS
        Tests whether a projected value can carry a YAML ToString member.

        .DESCRIPTION
        Reports whether a projected value is a mapping or a sequence, which are the
        shapes that gain a readable YAML rendering from ToString. Scalars, null, and
        binary values are rejected so the module never changes how an ordinary string,
        number, date, or byte array converts to text.

        .EXAMPLE
        Test-YamlDocumentSurface -Value ([pscustomobject]@{ name = 'Ada' })

        Returns true because a mapping renders as a YAML block.

        .EXAMPLE
        Test-YamlDocumentSurface -Value 42

        Returns false because a scalar keeps its own ToString.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # The projected value whose YAML rendering eligibility is tested.
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return $false
    }
    if ($Value -is [System.Management.Automation.PSCustomObject]) {
        return $true
    }
    if ($Value -is [System.Collections.IDictionary]) {
        return $true
    }
    if ($Value -is [byte[]] -or $Value -is [string] -or $Value -is [char]) {
        return $false
    }

    $Value -is [System.Collections.IEnumerable]
}
