function Merge-YamlRepresentationNode {
    <#
        .SYNOPSIS
        Merges one later YAML representation node into an existing cloned node.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates only an isolated in-memory merge graph.'
    )]
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $BaseNode,

        [Parameter(Mandatory)]
        [pscustomobject] $OverlayNode,

        [Parameter(Mandatory)]
        [ValidateSet('Replace', 'Append', 'Unique')]
        [string] $SequenceAction,

        [Parameter(Mandatory)]
        [ValidateSet('Replace', 'Error')]
        [string] $ConflictAction,

        [Parameter(Mandatory)]
        [ValidateSet('Replace', 'Ignore')]
        [string] $NullAction,

        [Parameter(Mandatory)]
        [string] $Path,

        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $Context.WorkState.MergeCount++
    if ($Context.WorkState.MergeCount -gt $Context.WorkState.MaxNodes) {
        throw (New-YamlMergeException -Node $OverlayNode -ErrorId 'YamlMergeNodeLimitExceeded' -Message (
                "Merging input index $($Context.InputIndex) document index $($Context.DocumentIndex) " +
                "exceeded the configured work limit of $($Context.WorkState.MaxNodes) nodes."
            ))
    }

    $base = Get-YamlMergeNode -Node $BaseNode
    $overlay = Get-YamlMergeNode -Node $OverlayNode
    $overlayTag = Get-YamlMergeNodeTag -Node $overlay
    if ($NullAction -eq 'Ignore' -and
        $overlayTag -ceq 'tag:yaml.org,2002:null') {
        Write-Output -InputObject $BaseNode -NoEnumerate
        return
    }

    if (Test-YamlMergeNodeEqual -Node $base -OtherNode $overlay `
            -State $Context.EqualityState) {
        if ($overlay.Kind -ne 'Scalar' -and
            -not $Context.CloneCache.ContainsKey($overlay.Id)) {
            $Context.CloneCache[$overlay.Id] = $base
        }
        Write-Output -InputObject $BaseNode -NoEnumerate
        return
    }

    $baseTag = Get-YamlMergeNodeTag -Node $base
    $isCompatible = $base.Kind -ceq $overlay.Kind -and $baseTag -ceq $overlayTag
    if (-not $isCompatible) {
        if ($ConflictAction -eq 'Error') {
            throw (New-YamlMergeException -Node $overlay -ErrorId 'YamlMergeConflict' -Message (
                    "YAML merge conflict at $Path in input index $($Context.InputIndex), " +
                    "document index $($Context.DocumentIndex): $($base.Kind.ToLowerInvariant()) " +
                    "tag '$baseTag' conflicts with $($overlay.Kind.ToLowerInvariant()) tag '$overlayTag'."
                ))
        }
        return Copy-YamlMergeNode -Node $OverlayNode -Cache $Context.CloneCache `
            -State $Context.CloneState
    }

    if ($base.Kind -eq 'Scalar') {
        if ($ConflictAction -eq 'Error') {
            throw (New-YamlMergeException -Node $overlay -ErrorId 'YamlMergeConflict' -Message (
                    "YAML merge conflict at $Path in input index $($Context.InputIndex), " +
                    "document index $($Context.DocumentIndex): unequal scalar values use tag '$baseTag'."
                ))
        }
        return Copy-YamlMergeNode -Node $OverlayNode -Cache $Context.CloneCache `
            -State $Context.CloneState
    }

    if ($base.Kind -eq 'Sequence' -and $SequenceAction -eq 'Replace') {
        return Copy-YamlMergeNode -Node $OverlayNode -Cache $Context.CloneCache `
            -State $Context.CloneState
    }

    if ($Context.CloneCache.ContainsKey($overlay.Id)) {
        if ($OverlayNode.Kind -eq 'Alias') {
            return Copy-YamlMergeNode -Node $OverlayNode -Cache $Context.CloneCache `
                -State $Context.CloneState
        }
        Write-Output -InputObject $Context.CloneCache[$overlay.Id] -NoEnumerate
        return
    }
    $Context.CloneCache[$overlay.Id] = $base

    if ($base.Kind -eq 'Sequence') {
        if ($SequenceAction -eq 'Append') {
            foreach ($item in $overlay.Items) {
                $copy = Copy-YamlMergeNode -Node $item -Cache $Context.CloneCache `
                    -State $Context.CloneState
                $base.Items.Add($copy)
            }
            Write-Output -InputObject $BaseNode -NoEnumerate
            return
        }

        $retained = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        foreach ($item in $base.Items) {
            $fingerprint = Get-YamlMergeFingerprint -Node $item -State $Context.EqualityState
            if (-not $retained.ContainsKey($fingerprint)) {
                $retained[$fingerprint] = [System.Collections.Generic.List[object]]::new()
            }
            $retained[$fingerprint].Add($item)
        }
        foreach ($item in $overlay.Items) {
            $fingerprint = Get-YamlMergeFingerprint -Node $item -State $Context.EqualityState
            $exists = $false
            if ($retained.ContainsKey($fingerprint)) {
                foreach ($candidate in $retained[$fingerprint]) {
                    if (Test-YamlMergeNodeEqual -Node $candidate -OtherNode $item `
                            -State $Context.EqualityState) {
                        $exists = $true
                        break
                    }
                }
            }
            if ($exists) {
                continue
            }
            $copy = Copy-YamlMergeNode -Node $item -Cache $Context.CloneCache `
                -State $Context.CloneState
            $base.Items.Add($copy)
            if (-not $retained.ContainsKey($fingerprint)) {
                $retained[$fingerprint] = [System.Collections.Generic.List[object]]::new()
            }
            $retained[$fingerprint].Add($copy)
        }
        Write-Output -InputObject $BaseNode -NoEnumerate
        return
    }

    $entries = [System.Collections.Generic.Dictionary[string, object]]::new(
        [System.StringComparer]::Ordinal
    )
    foreach ($entry in $base.Entries) {
        $fingerprint = Get-YamlMergeFingerprint -Node $entry.Key -State $Context.EqualityState
        if (-not $entries.ContainsKey($fingerprint)) {
            $entries[$fingerprint] = [System.Collections.Generic.List[object]]::new()
        }
        $entries[$fingerprint].Add($entry)
    }

    for ($index = 0; $index -lt $overlay.Entries.Count; $index++) {
        $overlayEntry = $overlay.Entries[$index]
        $fingerprint = Get-YamlMergeFingerprint -Node $overlayEntry.Key `
            -State $Context.EqualityState
        $match = $null
        if ($entries.ContainsKey($fingerprint)) {
            foreach ($candidate in $entries[$fingerprint]) {
                if (Test-YamlMergeNodeEqual -Node $candidate.Key -OtherNode $overlayEntry.Key `
                        -State $Context.EqualityState) {
                    $match = $candidate
                    break
                }
            }
        }

        if ($null -ne $match) {
            $childPath = Get-YamlMergePath -Parent $Path -Key $overlayEntry.Key -Index $index
            $match.Value = Merge-YamlRepresentationNode -BaseNode $match.Value `
                -OverlayNode $overlayEntry.Value -SequenceAction $SequenceAction `
                -ConflictAction $ConflictAction -NullAction $NullAction -Path $childPath `
                -Context $Context
            continue
        }

        $keyCopy = Copy-YamlMergeNode -Node $overlayEntry.Key -Cache $Context.CloneCache `
            -State $Context.CloneState
        $valueCopy = Copy-YamlMergeNode -Node $overlayEntry.Value -Cache $Context.CloneCache `
            -State $Context.CloneState
        $newEntry = [pscustomobject]@{ Key = $keyCopy; Value = $valueCopy }
        $base.Entries.Add($newEntry)
        if (-not $entries.ContainsKey($fingerprint)) {
            $entries[$fingerprint] = [System.Collections.Generic.List[object]]::new()
        }
        $entries[$fingerprint].Add($newEntry)
    }

    Write-Output -InputObject $BaseNode -NoEnumerate
}
