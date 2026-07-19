function Test-YamlNodeGraph {
    <#
        .SYNOPSIS
        Validates tags and mapping-key uniqueness in a YAML node graph.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[int]] $Visited,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[int, string]] $FingerprintCache,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.HashAlgorithm] $FingerprintHasher
    )

    if ($Node.Kind -eq 'Alias') {
        Test-YamlNodeGraph -Node $Node.Target -Visited $Visited -FingerprintCache $FingerprintCache `
            -FingerprintHasher $FingerprintHasher
        return
    }
    if (-not $Visited.Add($Node.Id)) {
        return
    }

    $scalarTags = @(
        'tag:yaml.org,2002:binary',
        'tag:yaml.org,2002:bool',
        'tag:yaml.org,2002:float',
        'tag:yaml.org,2002:int',
        'tag:yaml.org,2002:null',
        'tag:yaml.org,2002:str',
        'tag:yaml.org,2002:timestamp'
    )
    $tag = [string] $Node.Tag

    if ($Node.Kind -eq 'Scalar') {
        if ($tag -in @(
                'tag:yaml.org,2002:map',
                'tag:yaml.org,2002:omap',
                'tag:yaml.org,2002:pairs',
                'tag:yaml.org,2002:seq',
                'tag:yaml.org,2002:set'
            )) {
            throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlTagKindMismatch' -Message (
                    "YAML tag '$tag' cannot be applied to a scalar node."
                ))
        }
        $null = Resolve-YamlScalar -Node $Node
        return
    }

    if ($tag -in $scalarTags) {
        throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlTagKindMismatch' -Message (
                "YAML tag '$tag' cannot be applied to a $($Node.Kind.ToLowerInvariant()) node."
            ))
    }

    if ($Node.Kind -eq 'Sequence') {
        if ($tag -in @('tag:yaml.org,2002:map', 'tag:yaml.org,2002:set')) {
            throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlTagKindMismatch' -Message (
                    "YAML tag '$tag' requires a mapping node."
                ))
        }

        $isPairs = $tag -eq 'tag:yaml.org,2002:pairs'
        $isOrderedMap = $tag -eq 'tag:yaml.org,2002:omap'
        $orderedKeys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
        foreach ($item in $Node.Items) {
            Test-YamlNodeGraph -Node $item -Visited $Visited -FingerprintCache $FingerprintCache `
                -FingerprintHasher $FingerprintHasher
            if ($isPairs -or $isOrderedMap) {
                $entryNode = $item
                while ($entryNode.Kind -eq 'Alias') {
                    $entryNode = $entryNode.Target
                }
                if ($entryNode.Kind -ne 'Mapping' -or $entryNode.Entries.Count -ne 1) {
                    throw (New-YamlException -Start $item.Start -End $item.End -ErrorId 'YamlInvalidTaggedCollection' -Message (
                            "YAML tag '$tag' requires a sequence of one-entry mappings."
                        ))
                }
                if ($isOrderedMap) {
                    $keyFingerprint = Get-YamlNodeFingerprint -Node $entryNode.Entries[0].Key -Active (
                        [System.Collections.Generic.HashSet[int]]::new()
                    ) -Cache $FingerprintCache -Hasher $FingerprintHasher
                    if (-not $orderedKeys.Add($keyFingerprint)) {
                        $keyNode = $entryNode.Entries[0].Key
                        $exception = New-YamlException -Start $keyNode.Start -End $keyNode.End `
                            -ErrorId 'YamlDuplicateKey' -Message 'A duplicate key was found in a YAML ordered mapping.'
                        throw $exception
                    }
                }
            }
        }
        return
    }

    if ($tag -in @(
            'tag:yaml.org,2002:omap',
            'tag:yaml.org,2002:pairs',
            'tag:yaml.org,2002:seq'
        )) {
        throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlTagKindMismatch' -Message (
                "YAML tag '$tag' requires a sequence node."
            ))
    }

    $keys = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $Node.Entries) {
        $fingerprint = Get-YamlNodeFingerprint -Node $entry.Key -Active (
            [System.Collections.Generic.HashSet[int]]::new()
        ) -Cache $FingerprintCache -Hasher $FingerprintHasher
        if (-not $keys.Add($fingerprint)) {
            throw (New-YamlException -Start $entry.Key.Start -End $entry.Key.End -ErrorId 'YamlDuplicateKey' -Message (
                    'A duplicate mapping key is not allowed.'
                ))
        }

        Test-YamlNodeGraph -Node $entry.Key -Visited $Visited -FingerprintCache $FingerprintCache `
            -FingerprintHasher $FingerprintHasher
        Test-YamlNodeGraph -Node $entry.Value -Visited $Visited -FingerprintCache $FingerprintCache `
            -FingerprintHasher $FingerprintHasher

        if ($tag -eq 'tag:yaml.org,2002:set') {
            $setValue = $entry.Value
            while ($setValue.Kind -eq 'Alias') {
                $setValue = $setValue.Target
            }
            if ($setValue.Kind -ne 'Scalar' -or $null -ne (Resolve-YamlScalar -Node $setValue)) {
                throw (New-YamlException -Start $entry.Value.Start -End $entry.Value.End -ErrorId 'YamlInvalidTaggedCollection' -Message (
                        'Every value in a YAML set must be null.'
                    ))
            }
        }
    }
}
