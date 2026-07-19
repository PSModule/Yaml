function Confirm-YamlScalarLength {
    <#
        .SYNOPSIS
        Enforces the configured length limit for an emission scalar.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    if ($Node.Value.Length -gt $State.MaxScalarLength) {
        throw (New-YamlSerializationException -ErrorId 'YamlScalarLimitExceeded' -Message (
                "A scalar exceeds the configured limit of $($State.MaxScalarLength) characters."
            ))
    }
}
