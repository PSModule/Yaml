function Assert-YamlNodeKeyUnique {
    <#
        .SYNOPSIS
        Indexes one representation key and confirms equality for fingerprint candidates.

        .DESCRIPTION
        Computes a structural fingerprint for one YAML mapping key and stores it
        in duplicate-detection buckets. When a matching fingerprint already exists
        in the bucket, it throws a duplicate-key YAML error.

        .EXAMPLE
        Assert-YamlNodeKeyUnique -Node $keyNode -Buckets $buckets -FingerprintCache $fingerprints `
            -FingerprintHasher ([System.Security.Cryptography.SHA256]::Create()) -DuplicateMessage 'Duplicate mapping key.'

        Returns nothing and indexes the key when no equal mapping key is present.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    param (
        # The mapping key node that must be unique in its containing mapping.
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        # The fingerprint buckets used to find candidate duplicate keys quickly.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[string, object]] $Buckets,

        # The reusable fingerprint cache that avoids rehashing shared YAML nodes.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[int, string]] $FingerprintCache,

        # The hash algorithm shared by duplicate-key fingerprint operations.
        [Parameter(Mandatory)]
        [System.Security.Cryptography.HashAlgorithm] $FingerprintHasher,

        # The context-specific message to throw when this key duplicates another.
        [Parameter(Mandatory)]
        [string] $DuplicateMessage
    )

    $fingerprint = Get-YamlNodeFingerprint -Node $Node `
        -Active ([System.Collections.Generic.HashSet[int]]::new()) `
        -Cache $FingerprintCache -Hasher $FingerprintHasher
    $bucket = $null
    if (-not $Buckets.TryGetValue($fingerprint, [ref] $bucket)) {
        $bucket = [System.Collections.Generic.List[object]]::new()
        $Buckets[$fingerprint] = $bucket
    } else {
        throw (New-YamlException -Start $Node.Start -End $Node.End `
                -ErrorId 'YamlDuplicateKey' -Message $DuplicateMessage)
    }
    $bucket.Add($Node)
}
