function Get-YamlNodeFingerprint {
    <#
        .SYNOPSIS
        Creates a structural fingerprint for YAML duplicate-key detection.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[int]] $Active,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[int, string]] $Cache,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.HashAlgorithm] $Hasher
    )

    if ($Node.Kind -eq 'Alias') {
        return Get-YamlNodeFingerprint -Node $Node.Target -Active $Active -Cache $Cache -Hasher $Hasher
    }

    $cachedFingerprint = ''
    if ($Cache.TryGetValue($Node.Id, [ref] $cachedFingerprint)) {
        return $cachedFingerprint
    }

    if (-not $Active.Add($Node.Id)) {
        throw (New-YamlException -Start $Node.Start -End $Node.End -ErrorId 'YamlCyclicMappingKey' -Message (
                'A cyclic YAML node cannot be used as a mapping key.'
            ))
    }

    try {
        if ($Node.Kind -eq 'Scalar') {
            $resolved = Resolve-YamlScalar -Node $Node
            $fingerprint = Get-YamlScalarFingerprint -Value $resolved -Hasher $Hasher
        } elseif ($Node.Kind -eq 'Sequence') {
            $parts = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $Node.Items) {
                $itemFingerprint = Get-YamlNodeFingerprint -Node $item -Active $Active -Cache $Cache -Hasher $Hasher
                $parts.Add($itemFingerprint)
            }
            $semanticTag = if ($Node.Tag -in @(
                    'tag:yaml.org,2002:omap',
                    'tag:yaml.org,2002:pairs'
                )) { $Node.Tag } else { 'tag:yaml.org,2002:seq' }
            $canonicalValue = 'sequence:{0}:{1}' -f $semanticTag, ($parts -join '|')
            $fingerprint = Get-YamlFingerprintHash -Value $canonicalValue -Hasher $Hasher
        } else {
            $entries = [System.Collections.Generic.List[string]]::new()
            foreach ($entry in $Node.Entries) {
                $key = Get-YamlNodeFingerprint -Node $entry.Key -Active $Active -Cache $Cache -Hasher $Hasher
                $entryValue = Get-YamlNodeFingerprint -Node $entry.Value -Active $Active -Cache $Cache -Hasher $Hasher
                $entryFingerprint = Get-YamlFingerprintHash -Value "entry:$key=$entryValue" -Hasher $Hasher
                $entries.Add($entryFingerprint)
            }
            $entries.Sort([System.StringComparer]::Ordinal)
            $mappingTag = if ($Node.Tag -eq 'tag:yaml.org,2002:set') {
                $Node.Tag
            } else {
                'tag:yaml.org,2002:map'
            }
            $canonicalValue = 'mapping:{0}:{1}' -f $mappingTag, ($entries -join '|')
            $fingerprint = Get-YamlFingerprintHash -Value $canonicalValue -Hasher $Hasher
        }

        $Cache[$Node.Id] = $fingerprint
        return $fingerprint
    } finally {
        [void] $Active.Remove($Node.Id)
    }
}
