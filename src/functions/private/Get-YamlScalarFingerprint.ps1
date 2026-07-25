function Get-YamlScalarFingerprint {
    <#
        .SYNOPSIS
        Creates a canonical fingerprint for a resolved YAML scalar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

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
