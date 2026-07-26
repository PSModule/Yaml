function Assert-YamlNodeKeyUnique {
    <#
        .SYNOPSIS
        Indexes one representation key and confirms equality for fingerprint candidates.

        .DESCRIPTION
        Computes a structural fingerprint for one YAML mapping key and stores it
        in duplicate-detection buckets. When a fingerprint already exists, it
        either rejects the key immediately or confirms equality with merge-aware
        graph comparison before throwing a duplicate-key YAML error.

        .EXAMPLE
        Assert-YamlNodeKeyUnique -Node $keyNode -Buckets $buckets -FingerprintCache $fingerprints -FingerprintHasher ([System.Security.Cryptography.SHA256]::Create()) -DuplicateMessage 'Duplicate mapping key.'

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
        [string] $DuplicateMessage,

        # Optional merge/remove work tracker used to charge fingerprint effort.
        [Parameter()]
        [AllowNull()]
        [pscustomobject] $RemovalWorkState,

        # Optional graph equality state for confirming merge candidate collisions.
        [Parameter()]
        [AllowNull()]
        [pscustomobject] $EqualityState,

        # Optional equality fingerprint cache shared by both comparison sides.
        [Parameter()]
        [AllowNull()]
        [System.Collections.Generic.Dictionary[int, string]] $EqualityFingerprintCache
    )

    $fingerprint = Get-YamlNodeFingerprint -Node $Node `
        -Active ([System.Collections.Generic.HashSet[int]]::new()) `
        -Cache $FingerprintCache -Hasher $FingerprintHasher `
        -RemovalWorkState $RemovalWorkState
    $bucket = $null
    if (-not $Buckets.TryGetValue($fingerprint, [ref] $bucket)) {
        $bucket = [System.Collections.Generic.List[object]]::new()
        $Buckets[$fingerprint] = $bucket
    } elseif ($null -eq $EqualityState) {
        throw (New-YamlException -Start $Node.Start -End $Node.End `
                -ErrorId 'YamlDuplicateKey' -Message $DuplicateMessage)
    } else {
        foreach ($candidate in $bucket) {
            if (Test-YamlMergeNodeEqual -Node $candidate -OtherNode $Node `
                    -State $EqualityState `
                    -LeftFingerprintCache $EqualityFingerprintCache `
                    -RightFingerprintCache $EqualityFingerprintCache) {
                throw (New-YamlException -Start $Node.Start -End $Node.End `
                        -ErrorId 'YamlDuplicateKey' -Message $DuplicateMessage)
            }
        }
    }
    $bucket.Add($Node)
}
