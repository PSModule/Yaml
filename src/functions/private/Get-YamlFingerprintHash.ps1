function Get-YamlFingerprintHash {
    <#
        .SYNOPSIS
        Hashes canonical YAML fingerprint input to a fixed-size digest.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Value,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.HashAlgorithm] $Hasher
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    return [System.Convert]::ToBase64String($Hasher.ComputeHash($bytes))
}
