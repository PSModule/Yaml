function Get-YamlMergeFingerprint {
    <#
        .SYNOPSIS
        Creates a deterministic candidate index for structural merge comparisons.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [pscustomobject] $State
    )

    $effective = Get-YamlMergeNode -Node $Node
    $tag = Get-YamlMergeNodeTag -Node $effective
    if ($effective.Kind -eq 'Scalar') {
        $resolved = (Resolve-YamlScalar -Node $effective).Value
        $value = Get-YamlScalarFingerprint -Value $resolved -Hasher $State.FingerprintHasher
        return 'scalar:{0}:{1}:{2}' -f $tag.Length, $tag, $value
    }

    $count = if ($effective.Kind -eq 'Sequence') {
        $effective.Items.Count
    } else {
        $effective.Entries.Count
    }
    return '{0}:{1}:{2}:{3}' -f $effective.Kind.ToLowerInvariant(), $tag.Length, $tag, $count
}
