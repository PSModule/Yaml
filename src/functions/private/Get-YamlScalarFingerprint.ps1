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
    } elseif ($Value -is [decimal]) {
        if ($Value -eq 0 -and
            ([decimal]::GetBits($Value)[3] -band [int]::MinValue) -ne 0) {
            $canonicalValue = 'float:-0'
        } else {
            $canonicalValue = 'float:{0}' -f $Value.ToString(
                'G29',
                [cultureinfo]::InvariantCulture
            )
        }
    } elseif ($Value -is [double]) {
        if ([double]::IsNaN($Value)) {
            $canonicalValue = 'float:nan'
        } elseif ([double]::IsPositiveInfinity($Value)) {
            $canonicalValue = 'float:+inf'
        } elseif ([double]::IsNegativeInfinity($Value)) {
            $canonicalValue = 'float:-inf'
        } elseif ($Value -eq 0) {
            $negative = [System.BitConverter]::DoubleToInt64Bits([double] $Value) -lt 0
            $canonicalValue = if ($negative) { 'float:-0' } else { 'float:0' }
        } else {
            $canonicalValue = 'float:{0}' -f $Value.ToString(
                'R',
                [cultureinfo]::InvariantCulture
            )
        }
    } else {
        $canonicalValue = 'int:{0}' -f $Value.ToString([cultureinfo]::InvariantCulture)
    }

    return Get-YamlFingerprintHash -Value $canonicalValue -Hasher $Hasher
}
