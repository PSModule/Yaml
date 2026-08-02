function Confirm-YamlScalarLength {
    <#
        .SYNOPSIS
        Enforces the configured length limit for an emission scalar.

        .DESCRIPTION
        Checks a scalar node against the active serializer length budget before
        emission. This prevents generated YAML from silently exceeding the
        configured maximum scalar size.

        .EXAMPLE
        Confirm-YamlScalarLength -Node ([pscustomobject]@{ Value = 'name' }) -State ([pscustomobject]@{ MaxScalarLength = 1024 })

        Returns nothing because the scalar value is within the configured limit.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    param (
        # The scalar node whose text length must fit the emission budget.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # The serializer state that carries the configured maximum scalar length.
        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    if ($Node.Value.Length -gt $State.MaxScalarLength) {
        throw (New-YamlSerializationException -ErrorId 'YamlScalarLimitExceeded' -Message (
                "A scalar exceeds the configured limit of $($State.MaxScalarLength) characters."
            ))
    }
}
