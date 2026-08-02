function Get-YamlFingerprintHash {
    <#
        .SYNOPSIS
        Hashes canonical YAML fingerprint input to a fixed-size digest.

        .DESCRIPTION
        Encodes canonical fingerprint text as UTF-8 and hashes it with the supplied reusable
        algorithm. The fixed-size Base64 digest keeps emission fingerprints comparable and compact
        while traversing large graphs.

        .EXAMPLE
        Get-YamlFingerprintHash -Value 'scalar:3:str:3:Ada' -Hasher $sha256

        Returns the Base64 digest for the canonical fingerprint input.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The canonical fingerprint text is hashed so callers compare fixed-size values.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        # The caller-provided hash algorithm defines the digest used across one emission pass.
        [Parameter(Mandatory)]
        [System.Security.Cryptography.HashAlgorithm] $Hasher
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return [System.Convert]::ToBase64String($Hasher.ComputeHash($bytes))
}
