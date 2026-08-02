function Get-YamlScalarFingerprint {
    <#
        .SYNOPSIS
        Creates a canonical fingerprint for a resolved YAML scalar.

        .DESCRIPTION
        Converts a resolved scalar value into a type-aware canonical string and hashes it. The
        fingerprint prevents equivalent YAML scalars from being treated as different anchor
        candidates because of presentation differences.

        .EXAMPLE
        Get-YamlScalarFingerprint -Value ([datetime]'2024-01-01T00:00:00Z') -Hasher $sha256

        Returns the canonical scalar fingerprint for the resolved timestamp value.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The resolved scalar value is canonicalized so equal YAML values hash identically.
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

        # The reusable hash algorithm keeps scalar fingerprints compatible with node fingerprints.
        [Parameter(Mandatory)]
        [System.Security.Cryptography.HashAlgorithm] $Hasher
    )

    if ($null -eq $Value) {
        $canonicalValue = 'null'
    } elseif ($Value -is [string]) {
        $canonicalValue = 'str:{0}:{1}' -f $Value.Length, $Value
    } elseif ($Value -is [bool]) {
        $canonicalValue = 'bool:{0}' -f $Value.ToString().ToLowerInvariant()
    } elseif ($Value -is [byte[]]) {
        $canonicalValue = 'binary:{0}' -f [System.Convert]::ToBase64String($Value)
    } elseif ($Value -is [datetimeoffset]) {
        $canonicalValue = 'timestamp:{0}' -f $Value.UtcDateTime.Ticks
    } elseif ($Value -is [datetime]) {
        $utcValue = if ($Value.Kind -eq [System.DateTimeKind]::Utc) {
            $Value
        } elseif ($Value.Kind -eq [System.DateTimeKind]::Local) {
            $Value.ToUniversalTime()
        } else {
            [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
        }
        $canonicalValue = 'timestamp:{0}' -f $utcValue.Ticks
    } elseif ($Value -is [decimal] -or $Value -is [double] -or $Value -is [single]) {
        $canonicalValue = 'float:{0}' -f (Get-YamlNormalizedFloat -Value $Value)
    } else {
        $canonicalValue = 'int:{0}' -f $Value.ToString([cultureinfo]::InvariantCulture)
    }

    return Get-YamlFingerprintHash -Value $canonicalValue -Hasher $Hasher
}
