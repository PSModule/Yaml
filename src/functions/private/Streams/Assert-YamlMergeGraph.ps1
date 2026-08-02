function Assert-YamlMergeGraph {
    <#
        .SYNOPSIS
        Validates the merged representation graph and its resource budgets.

        .DESCRIPTION
        Walks merged documents to enforce final depth, node, alias, scalar, and
        tag budgets before emission. It also delegates graph validation so
        recursive or shared representation structures remain safe and well-formed
        after merging.

        .EXAMPLE
        Assert-YamlMergeGraph -Documents $mergedDocuments -Depth 100 -MaxNodes 100000 `
            -MaxAliases 1000 -MaxScalarLength 1048576 -MaxTagLength 1024 -MaxTotalTagLength 65536

        Validates the merged document graph and throws a classified YAML merge
        exception if any limit is exceeded.

        .LINK
        https://psmodule.io/Yaml/Functions/Streams/Merge-Yaml/
    #>
    [CmdletBinding()]
    param (
        # The merged document roots to validate as one resulting YAML stream.
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Documents,

        # Limits traversal depth so deeply nested results cannot exhaust consumers.
        [Parameter(Mandatory)]
        [int] $Depth,

        # Caps unique representation nodes in the result graph.
        [Parameter(Mandatory)]
        [int] $MaxNodes,

        # Caps alias nodes after merge to keep reference expansion bounded.
        [Parameter(Mandatory)]
        [int] $MaxAliases,

        # Caps decoded scalar size before the merged stream is emitted.
        [Parameter(Mandatory)]
        [int] $MaxScalarLength,

        # Caps each expanded tag length in the merged graph.
        [Parameter(Mandatory)]
        [int] $MaxTagLength,

        # Caps cumulative expanded tag text across the result graph.
        [Parameter(Mandatory)]
        [int] $MaxTotalTagLength
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
        if (-not $visited.Add($node.Id)) {
            continue
        }
        $nodeCount++
        if ($nodeCount -gt $MaxNodes) {
            throw (New-YamlMergeException -Node $node -ErrorId 'YamlMergeNodeLimitExceeded' -Message (
                    "The merged YAML graph exceeds the configured limit of $MaxNodes nodes."
                ))
        }
        if ($item.Depth -gt $Depth) {
            throw (New-YamlMergeException -Node $node -ErrorId 'YamlMergeDepthLimitExceeded' -Message (
                    "The merged YAML graph exceeds the configured depth of $Depth."
                ))
        }

        if ($node.Kind -eq 'Alias') {
            $aliasCount++
            if ($aliasCount -gt $MaxAliases) {
                throw (New-YamlMergeException -Node $node -ErrorId 'YamlMergeAliasLimitExceeded' -Message (
                        "The merged YAML graph exceeds the configured limit of $MaxAliases aliases."
                    ))
            }
            $pending.Push([pscustomobject]@{ Node = $node.Target; Depth = $item.Depth })
            continue
        }

        $tagLength = ([string] $node.Tag).Length
        if ($tagLength -gt $MaxTagLength) {
            throw (New-YamlMergeException -Node $node -ErrorId 'YamlMergeTagLimitExceeded' -Message (
                    "A tag in the merged YAML graph exceeds the configured limit of $MaxTagLength characters."
                ))
        }
        $totalTagLength += $tagLength
        if ($totalTagLength -gt $MaxTotalTagLength) {
            throw (New-YamlMergeException -Node $node -ErrorId 'YamlMergeTagLimitExceeded' -Message (
                    "The merged YAML graph exceeds the configured cumulative tag limit of " +
                    "$MaxTotalTagLength characters."
                ))
        }

        if ($node.Kind -eq 'Scalar') {
            if ((Get-YamlRuneCount -Text ([string] $node.Value)) -gt $MaxScalarLength) {
                throw (New-YamlMergeException -Node $node `
                        -ErrorId 'YamlMergeScalarLimitExceeded' -Message (
                        "A scalar in the merged YAML graph exceeds the configured limit of " +
                        "$MaxScalarLength characters."
                    ))
            }
            continue
        }
        if ($node.Kind -eq 'Sequence') {
            for ($index = $node.Items.Count - 1; $index -ge 0; $index--) {
                $pending.Push([pscustomobject]@{
                        Node  = $node.Items[$index]
                        Depth = $item.Depth + 1
                    })
            }
            continue
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
    try {
        foreach ($document in $Documents) {
            Test-YamlNodeGraph -Node $document `
                -Visited ([System.Collections.Generic.HashSet[int]]::new()) `
                -FingerprintCache $fingerprintCache -FingerprintHasher $fingerprintHasher
        }
    } finally {
        $fingerprintHasher.Dispose()
    }
}
