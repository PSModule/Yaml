function Assert-YamlRemovalGraph {
    <#
        .SYNOPSIS
        Validates a removed representation graph and its resource budgets.

        .DESCRIPTION
        Traverses the post-removal representation graph to enforce depth, node,
        alias, scalar, and tag limits before emitting YAML. It also rechecks
        tagged collection invariants and duplicate-key comparisons so removed
        output remains valid and deterministic.

        .EXAMPLE
        Assert-YamlRemovalGraph -Documents $documents -Depth 100 -MaxNodes 100000 -MaxAliases 1000 -MaxScalarLength 1048576 -MaxTagLength 1024 -MaxTotalTagLength 65536 -State $state

        Validates the mutated documents and throws a classified removal exception if an output limit is exceeded.

        .LINK
        https://psmodule.io/Yaml/Functions/Remove-YamlEntry/
    #>
    [CmdletBinding()]
    param (
        # The post-removal document roots are walked so validation covers exactly
        # what will be emitted.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Documents,

        # The depth limit prevents a removal result from producing an over-deep
        # graph.
        [Parameter(Mandatory)]
        [int] $Depth,

        # The node limit bounds traversal, duplicate-key comparison, and output
        # graph size.
        [Parameter(Mandatory)]
        [int] $MaxNodes,

        # The alias limit keeps emitted alias count within the caller's resource
        # budget.
        [Parameter(Mandatory)]
        [int] $MaxAliases,

        # The scalar length limit rejects oversized decoded scalar content after
        # mutation.
        [Parameter(Mandatory)]
        [int] $MaxScalarLength,

        # The per-tag limit prevents an emitted node from carrying an oversized
        # expanded tag.
        [Parameter(Mandatory)]
        [int] $MaxTagLength,

        # The cumulative tag limit bounds total expanded tag text across the
        # output graph.
        [Parameter(Mandatory)]
        [int] $MaxTotalTagLength,

        # The shared removal work state accounts validation operations against
        # the invocation budget.
        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    $visited = [System.Collections.Generic.HashSet[int]]::new()
    $pending = [System.Collections.Generic.Stack[object]]::new()
    foreach ($document in $Documents) {
        $pending.Push([pscustomobject]@{ Node = $document; Depth = 1 })
    }
    $nodeCount = 0
    $aliasCount = 0
    $totalTagLength = 0L

    while ($pending.Count -gt 0) {
        $item = $pending.Pop()
        $node = $item.Node
        Add-YamlRemovalWork -State $State -Operation 'output validation' -Node $node
        if (-not $visited.Add($node.Id)) {
            continue
        }

        $nodeCount++
        if ($nodeCount -gt $MaxNodes) {
            throw (New-YamlRemovalException -Node $node `
                    -ErrorId 'YamlRemovalNodeLimitExceeded' -Message (
                    "The resulting YAML graph exceeds the configured limit of $MaxNodes nodes."
                ))
        }
        if ($item.Depth -gt $Depth) {
            throw (New-YamlRemovalException -Node $node `
                    -ErrorId 'YamlRemovalDepthLimitExceeded' -Message (
                    "The resulting YAML graph exceeds the configured depth of $Depth."
                ))
        }

        if ($node.Kind -eq 'Alias') {
            $aliasCount++
            if ($aliasCount -gt $MaxAliases) {
                throw (New-YamlRemovalException -Node $node `
                        -ErrorId 'YamlRemovalAliasLimitExceeded' -Message (
                        "The resulting YAML graph exceeds the configured limit of $MaxAliases aliases."
                    ))
            }
            $pending.Push([pscustomobject]@{ Node = $node.Target; Depth = $item.Depth })
            continue
        }

        $tagLength = ([string] $node.Tag).Length
        if ($tagLength -gt $MaxTagLength) {
            throw (New-YamlRemovalException -Node $node `
                    -ErrorId 'YamlRemovalTagLimitExceeded' -Message (
                    "A tag in the resulting YAML graph exceeds the configured limit of " +
                    "$MaxTagLength characters."
                ))
        }
        $totalTagLength += $tagLength
        if ($totalTagLength -gt $MaxTotalTagLength) {
            throw (New-YamlRemovalException -Node $node `
                    -ErrorId 'YamlRemovalTagLimitExceeded' -Message (
                    "The resulting YAML graph exceeds the configured cumulative tag limit of " +
                    "$MaxTotalTagLength characters."
                ))
        }

        if ($node.Kind -eq 'Scalar') {
            if ((Get-YamlRuneCount -Text ([string] $node.Value)) -gt $MaxScalarLength) {
                throw (New-YamlRemovalException -Node $node `
                        -ErrorId 'YamlRemovalScalarLimitExceeded' -Message (
                        "A scalar in the resulting YAML graph exceeds the configured limit of " +
                        "$MaxScalarLength characters."
                    ))
            }
            continue
        }

        if ($node.Kind -eq 'Sequence') {
            if ($node.Tag -cin @(
                    'tag:yaml.org,2002:omap',
                    'tag:yaml.org,2002:pairs'
                )) {
                foreach ($sequenceItem in $node.Items) {
                    $effectiveItem = Get-YamlRemovalNode -Node $sequenceItem -State $State
                    if ($effectiveItem.Kind -ne 'Mapping' -or
                        $effectiveItem.Entries.Count -ne 1) {
                        throw (New-YamlException -Start $sequenceItem.Start `
                                -End $sequenceItem.End -ErrorId 'YamlInvalidTaggedCollection' `
                                -Message (
                                "YAML tag '$($node.Tag)' requires a sequence of one-entry mappings."
                            ))
                    }
                }
            }
            for ($index = $node.Items.Count - 1; $index -ge 0; $index--) {
                $pending.Push([pscustomobject]@{
                        Node  = $node.Items[$index]
                        Depth = $item.Depth + 1
                    })
            }
            continue
        }

        if ($node.Tag -ceq 'tag:yaml.org,2002:set') {
            foreach ($entry in $node.Entries) {
                $effectiveValue = Get-YamlRemovalNode -Node $entry.Value -State $State
                $resolvedValue = if ($effectiveValue.Kind -eq 'Scalar') {
                    (Resolve-YamlScalar -Node $effectiveValue).Value
                } else {
                    [System.Management.Automation.Internal.AutomationNull]::Value
                }
                if ($effectiveValue.Kind -ne 'Scalar' -or $null -ne $resolvedValue) {
                    throw (New-YamlException -Start $entry.Value.Start -End $entry.Value.End `
                            -ErrorId 'YamlInvalidTaggedCollection' -Message (
                            'Every value in a YAML set must be null.'
                        ))
                }
            }

        }
        for ($index = $node.Entries.Count - 1; $index -ge 0; $index--) {
            $pending.Push([pscustomobject]@{
                    Node  = $node.Entries[$index].Value
                    Depth = $item.Depth + 1
                })
            $pending.Push([pscustomobject]@{
                    Node  = $node.Entries[$index].Key
                    Depth = $item.Depth + 1
                })
        }
    }

    $fingerprintCache = [System.Collections.Generic.Dictionary[int, string]]::new()
    $fingerprintHasher = [System.Security.Cryptography.SHA256]::Create()
    $fingerprintWorkState = [pscustomobject]@{
        Count    = 0L
        MaxNodes = $MaxNodes
    }
    $equalityWorkState = [pscustomobject]@{
        Count    = 0L
        MaxNodes = $MaxNodes
    }
    $equalityState = [pscustomobject]@{
        MaxNodes          = $MaxNodes
        FingerprintHasher = $fingerprintHasher
        WorkState         = $equalityWorkState
        MutationState     = [pscustomobject]@{ Version = 0L }
        IndexDependents   = [System.Collections.Generic.Dictionary[int, object]]::new()
        Cache             = [System.Collections.Generic.Dictionary[string, bool]]::new(
            [System.StringComparer]::Ordinal
        )
        InputIndex        = 0
    }
    $equalityFingerprintCache = [System.Collections.Generic.Dictionary[int, string]]::new()
    try {
        foreach ($document in $Documents) {
            try {
                Test-YamlNodeGraph -Node $document `
                    -Visited ([System.Collections.Generic.HashSet[int]]::new()) `
                    -FingerprintCache $fingerprintCache -FingerprintHasher $fingerprintHasher `
                    -RemovalWorkState $fingerprintWorkState -EqualityState $equalityState `
                    -EqualityFingerprintCache $equalityFingerprintCache
            } catch {
                if ($_.Exception.Data.Contains('YamlErrorId') -and
                    $_.Exception.Data['YamlErrorId'] -ceq 'YamlMergeWorkLimitExceeded') {
                    $exception = New-YamlRemovalException -Node $document `
                        -ErrorId 'YamlRemovalWorkLimitExceeded' -Message (
                        'Post-removal duplicate-key graph comparison exceeded the configured ' +
                        "invocation work limit of $MaxNodes operations."
                    )
                    $exception.Data['YamlRemovalWorkCount'] = $equalityWorkState.Count
                    $exception.Data['YamlRemovalWorkLimit'] = $MaxNodes
                    $exception.Data['YamlRemovalWorkOperation'] = (
                        'duplicate-key graph comparison'
                    )
                    throw $exception
                }
                throw
            }
        }
    } finally {
        $fingerprintHasher.Dispose()
    }
}
