function Assert-YamlNodeKeyUnique {
    <#
        .SYNOPSIS
        Indexes one representation key and confirms equality for fingerprint candidates.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[string, object]] $Buckets,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[int, string]] $FingerprintCache,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.HashAlgorithm] $FingerprintHasher,

        [Parameter(Mandatory)]
        [string] $DuplicateMessage,

        [Parameter()]
        [AllowNull()]
        [pscustomobject] $RemovalWorkState,

        [Parameter()]
        [AllowNull()]
        [pscustomobject] $EqualityState,

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
