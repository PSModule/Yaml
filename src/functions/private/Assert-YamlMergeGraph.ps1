function Assert-YamlMergeGraph {
    <#
        .SYNOPSIS
        Validates the merged representation graph and its resource budgets.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Documents,

        [Parameter(Mandatory)]
        [int] $Depth,

        [Parameter(Mandatory)]
        [int] $MaxNodes,

        [Parameter(Mandatory)]
        [int] $MaxAliases,

        [Parameter(Mandatory)]
        [int] $MaxScalarLength,

        [Parameter(Mandatory)]
        [int] $MaxTagLength,

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
