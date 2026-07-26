function Get-YamlEmissionImplicitKeyLength {
    <#
        .SYNOPSIS
        Gets an emitted implicit key length in Unicode scalar values.

        .DESCRIPTION
        Counts Unicode scalar values in the already rendered key text. The emitter uses this to
        enforce YAML 1.2 implicit key length limits before choosing implicit or explicit key
        presentation.

        .EXAMPLE
        Get-YamlEmissionImplicitKeyLength -RenderedText 'name'

        Returns the number of Unicode scalar values that the rendered implicit key would occupy.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        # The rendered key text is measured after escaping so the limit matches emitted YAML.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $RenderedText
    )

    return Get-YamlRuneCount -Text $RenderedText
}
