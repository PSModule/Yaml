function Test-YamlNodeGraph {
    <#
        .SYNOPSIS
        Iteratively validates tags and mapping-key uniqueness.
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
        [System.Security.Cryptography.HashAlgorithm] $FingerprintHasher,

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

    $scalarTags = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($scalarTag in @('binary', 'bool', 'float', 'int', 'null', 'str', 'timestamp')) {
        [void] $scalarTags.Add("tag:yaml.org,2002:$scalarTag")
    }

    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push($Node)
    while ($stack.Count -gt 0) {
        $current = $stack.Pop()
        while ($current.Kind -eq 'Alias') {
            $current = $current.Target
        }
        if (-not $Visited.Add($current.Id)) {
            continue
        }

        $tag = [string] $current.Tag
        if ($current.Kind -eq 'Scalar') {
            if ($tag -cin @(
                    'tag:yaml.org,2002:map',
                    'tag:yaml.org,2002:omap',
                    'tag:yaml.org,2002:pairs',
                    'tag:yaml.org,2002:seq',
                    'tag:yaml.org,2002:set'
                )) {
                throw (New-YamlException -Start $current.Start -End $current.End `
                        -ErrorId 'YamlTagKindMismatch' -Message (
                        "YAML tag '$tag' cannot be applied to a scalar node."
                    ))
            }
            $null = Resolve-YamlScalar -Node $current
            continue
        }

        if ($scalarTags.Contains($tag)) {
            throw (New-YamlException -Start $current.Start -End $current.End `
                    -ErrorId 'YamlTagKindMismatch' -Message (
                    "YAML tag '$tag' cannot be applied to a $($current.Kind.ToLowerInvariant()) node."
                ))
        }

        if ($current.Kind -eq 'Sequence') {
            if ($tag -ceq 'tag:yaml.org,2002:map' -or
                $tag -ceq 'tag:yaml.org,2002:set') {
                throw (New-YamlException -Start $current.Start -End $current.End `
                        -ErrorId 'YamlTagKindMismatch' -Message (
                        "YAML tag '$tag' requires a mapping node."
                    ))
            }

            $isPairs = $tag -ceq 'tag:yaml.org,2002:pairs'
            $isOrderedMap = $tag -ceq 'tag:yaml.org,2002:omap'
            $orderedKeys = [System.Collections.Generic.Dictionary[string, object]]::new(
                [System.StringComparer]::Ordinal
            )
            for ($index = $current.Items.Count - 1; $index -ge 0; $index--) {
                $item = $current.Items[$index]
                if ($isPairs -or $isOrderedMap) {
                    $entryNode = $item
                    while ($entryNode.Kind -eq 'Alias') {
                        $entryNode = $entryNode.Target
                    }
                    if ($entryNode.Kind -ne 'Mapping' -or $entryNode.Entries.Count -ne 1) {
                        throw (New-YamlException -Start $item.Start -End $item.End `
                                -ErrorId 'YamlInvalidTaggedCollection' -Message (
                                "YAML tag '$tag' requires a sequence of one-entry mappings."
                            ))
                    }
                    if ($isOrderedMap) {
                        Assert-YamlNodeKeyUnique `
                            -Node $entryNode.Entries[0].Key `
                            -Buckets $orderedKeys -FingerprintCache $FingerprintCache `
                            -FingerprintHasher $FingerprintHasher `
                            -DuplicateMessage 'A duplicate key was found in a YAML ordered mapping.' `
                            -RemovalWorkState $RemovalWorkState -EqualityState $EqualityState `
                            -EqualityFingerprintCache $EqualityFingerprintCache
                    }
                }
                $stack.Push($item)
            }
            continue
        }

        if ($tag -cin @(
                'tag:yaml.org,2002:omap',
                'tag:yaml.org,2002:pairs',
                'tag:yaml.org,2002:seq'
            )) {
            throw (New-YamlException -Start $current.Start -End $current.End `
                    -ErrorId 'YamlTagKindMismatch' -Message (
                    "YAML tag '$tag' requires a sequence node."
                ))
        }

        $keys = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        for ($index = $current.Entries.Count - 1; $index -ge 0; $index--) {
            $entry = $current.Entries[$index]
            Assert-YamlNodeKeyUnique -Node $entry.Key -Buckets $keys `
                -FingerprintCache $FingerprintCache -FingerprintHasher $FingerprintHasher `
                -DuplicateMessage 'A duplicate mapping key is not allowed.' `
                -RemovalWorkState $RemovalWorkState -EqualityState $EqualityState `
                -EqualityFingerprintCache $EqualityFingerprintCache

            if ($tag -ceq 'tag:yaml.org,2002:set') {
                $setValue = $entry.Value
                while ($setValue.Kind -eq 'Alias') {
                    $setValue = $setValue.Target
                }
                $setScalar = if ($setValue.Kind -eq 'Scalar') {
                    Resolve-YamlScalar -Node $setValue
                } else {
                    $null
                }
                if ($setValue.Kind -ne 'Scalar' -or $null -ne $setScalar.Value) {
                    throw (New-YamlException -Start $entry.Value.Start -End $entry.Value.End `
                            -ErrorId 'YamlInvalidTaggedCollection' -Message (
                            'Every value in a YAML set must be null.'
                        ))
                }
            }
            $stack.Push($entry.Value)
            $stack.Push($entry.Key)
        }
    }
}
