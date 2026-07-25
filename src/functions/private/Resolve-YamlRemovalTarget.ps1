function Resolve-YamlRemovalTarget {
    <#
        .SYNOPSIS
        Resolves one decoded JSON Pointer against one YAML document.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Document,

        [Parameter(Mandatory)]
        [int] $DocumentIndex,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Pointer,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]] $Tokens,

        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    $documentKey = "D:$DocumentIndex"
    if ($Tokens.Count -eq 0) {
        return [pscustomobject]@{
            Found         = $true
            Key           = $documentKey
            Kind          = 'Document'
            Parent        = $null
            Index         = $DocumentIndex
            Edge          = $Document
            Node          = $Document
            Depth         = 0
            Path          = [string[]] @($documentKey)
            Pointer       = $Pointer
            DocumentIndex = $DocumentIndex
        }
    }

    $ancestors = [System.Collections.Generic.List[string]]::new()
    $ancestors.Add($documentKey)
    $current = $Document
    for ($tokenIndex = 0; $tokenIndex -lt $Tokens.Count; $tokenIndex++) {
        $token = $Tokens[$tokenIndex]
        $isFinal = $tokenIndex -eq $Tokens.Count - 1
        $effective = Get-YamlRemovalNode -Node $current -State $State
        Add-YamlRemovalWork -State $State -Operation 'pointer token resolution' `
            -Node $effective

        if ($effective.Kind -eq 'Mapping') {
            $hasUnaddressableKey = $false
            $matchingIndexes = [System.Collections.Generic.List[int]]::new()
            for ($entryIndex = 0; $entryIndex -lt $effective.Entries.Count; $entryIndex++) {
                $entry = $effective.Entries[$entryIndex]
                Add-YamlRemovalWork -State $State -Operation 'mapping key scan' `
                    -Node $entry.Key
                $keyNode = Get-YamlRemovalNode -Node $entry.Key -State $State
                if ($keyNode.Kind -ne 'Scalar') {
                    $hasUnaddressableKey = $true
                    continue
                }

                $resolvedKey = (Resolve-YamlScalar -Node $keyNode).Value
                $effectiveTag = Get-YamlEffectiveTag -Node $keyNode -Value $resolvedKey
                if (-not [string]::Equals(
                        $effectiveTag,
                        'tag:yaml.org,2002:str',
                        [System.StringComparison]::Ordinal
                    )) {
                    $hasUnaddressableKey = $true
                    continue
                }
                if ([string]::Equals(
                        [string] $keyNode.Value,
                        $token,
                        [System.StringComparison]::Ordinal
                    )) {
                    $matchingIndexes.Add($entryIndex)
                }
            }

            if ($matchingIndexes.Count -gt 1) {
                throw (New-YamlRemovalException -Node $effective `
                        -ErrorId 'YamlRemovalAmbiguousTarget' -Message (
                        "JSON Pointer '$Pointer' ambiguously matches more than one string key " +
                        "in YAML document index $DocumentIndex."
                    ))
            }
            if ($matchingIndexes.Count -eq 0) {
                $guidance = if ($hasUnaddressableKey) {
                    ' The mapping contains complex, non-string, or tagged keys that cannot be ' +
                    'addressed by JSON Pointer; no key was coerced or guessed.'
                } else {
                    ''
                }
                return [pscustomobject]@{
                    Found   = $false
                    ErrorId = 'YamlRemovalPathNotFound'
                    Message = (
                        "JSON Pointer '$Pointer' did not resolve in YAML document index " +
                        "$DocumentIndex at token '$token'.$guidance"
                    )
                    Node    = $effective
                }
            }

            $matchedIndex = $matchingIndexes[0]
            $matchedEntry = $effective.Entries[$matchedIndex]
            $edgeKey = "M:$($effective.Id):$matchedIndex"
            if ($isFinal) {
                return [pscustomobject]@{
                    Found         = $true
                    Key           = $edgeKey
                    Kind          = 'Mapping'
                    Parent        = $effective
                    Index         = $matchedIndex
                    Edge          = $matchedEntry
                    Node          = $matchedEntry.Value
                    Depth         = $Tokens.Count
                    Path          = [string[]] (@($ancestors.ToArray()) + $edgeKey)
                    Pointer       = $Pointer
                    DocumentIndex = $DocumentIndex
                }
            }
            $ancestors.Add($edgeKey)
            $current = $matchedEntry.Value
            continue
        }

        if ($effective.Kind -eq 'Sequence') {
            if ($token -cnotmatch '^(?:0|[1-9][0-9]*)$') {
                throw (New-YamlRemovalException -Node $effective `
                        -ErrorId 'YamlRemovalInvalidSequenceIndex' -Message (
                        "JSON Pointer token '$token' is not a canonical non-negative decimal " +
                        'YAML sequence index.'
                    ))
            }
            $sequenceIndex = 0
            if (-not [int]::TryParse(
                    $token,
                    [System.Globalization.NumberStyles]::None,
                    [System.Globalization.CultureInfo]::InvariantCulture,
                    [ref] $sequenceIndex
                )) {
                throw (New-YamlRemovalException -Node $effective `
                        -ErrorId 'YamlRemovalInvalidSequenceIndex' -Message (
                        "JSON Pointer token '$token' exceeds the supported YAML sequence index range."
                    ))
            }
            if ($sequenceIndex -ge $effective.Items.Count) {
                return [pscustomobject]@{
                    Found   = $false
                    ErrorId = 'YamlRemovalPathNotFound'
                    Message = (
                        "JSON Pointer '$Pointer' did not resolve in YAML document index " +
                        "$DocumentIndex because sequence index $sequenceIndex is out of range."
                    )
                    Node    = $effective
                }
            }

            $sequenceItem = $effective.Items[$sequenceIndex]
            $edgeKey = "S:$($effective.Id):$sequenceIndex"
            if ($isFinal) {
                return [pscustomobject]@{
                    Found         = $true
                    Key           = $edgeKey
                    Kind          = 'Sequence'
                    Parent        = $effective
                    Index         = $sequenceIndex
                    Edge          = $sequenceItem
                    Node          = $sequenceItem
                    Depth         = $Tokens.Count
                    Path          = [string[]] (@($ancestors.ToArray()) + $edgeKey)
                    Pointer       = $Pointer
                    DocumentIndex = $DocumentIndex
                }
            }
            $ancestors.Add($edgeKey)
            $current = $sequenceItem
            continue
        }

        return [pscustomobject]@{
            Found   = $false
            ErrorId = 'YamlRemovalPathNotFound'
            Message = (
                "JSON Pointer '$Pointer' did not resolve in YAML document index " +
                "$DocumentIndex because token '$token' traverses a scalar."
            )
            Node    = $effective
        }
    }
}
