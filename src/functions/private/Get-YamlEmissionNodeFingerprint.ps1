function Get-YamlEmissionNodeFingerprint {
    <#
        .SYNOPSIS
        Creates a structural fingerprint for a normalized emission node.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.Dictionary[long, string]] $Cache,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[long]] $Active,

        [Parameter(Mandatory)]
        [System.Security.Cryptography.HashAlgorithm] $Hasher
    )

    $hasReferenceId = $Node.ReferenceId -ne 0
    $cachedFingerprint = ''
    if ($hasReferenceId -and $Cache.TryGetValue($Node.ReferenceId, [ref] $cachedFingerprint)) {
        return $cachedFingerprint
    }
    if ($hasReferenceId -and -not $Active.Add($Node.ReferenceId)) {
        throw (New-YamlSerializationException -ErrorId 'YamlCycleDetected' -Message (
                'A cycle was detected while fingerprinting a YAML mapping key.'
            ))
    }

    try {
        if ($Node.Kind -eq 'Scalar') {
            $isPlainImplicit = [string]::IsNullOrEmpty($Node.Tag)
            $isPlainImplicit = $isPlainImplicit -and $Node.Style -eq [YamlDotNet.Core.ScalarStyle]::Plain
            $resolved = Resolve-YamlScalar -Node ([pscustomobject]@{
                    Tag             = $Node.Tag
                    Value           = $Node.Value
                    IsPlainImplicit = $isPlainImplicit
                    Start           = [YamlDotNet.Core.Mark]::Empty
                    End             = [YamlDotNet.Core.Mark]::Empty
                })
            $fingerprint = Get-YamlScalarFingerprint -Value $resolved -Hasher $Hasher
        } elseif ($Node.Kind -eq 'Sequence') {
            $parts = [System.Collections.Generic.List[string]]::new()
            foreach ($item in $Node.Items) {
                $itemFingerprint = Get-YamlEmissionNodeFingerprint -Node $item -Cache $Cache -Active $Active `
                    -Hasher $Hasher
                $parts.Add($itemFingerprint)
            }
            $fingerprint = Get-YamlFingerprintHash -Value ('sequence:{0}' -f ($parts -join '|')) -Hasher $Hasher
        } else {
            $entries = [System.Collections.Generic.List[string]]::new()
            foreach ($entry in $Node.Entries) {
                $keyFingerprint = Get-YamlEmissionNodeFingerprint -Node $entry.Key -Cache $Cache -Active $Active `
                    -Hasher $Hasher
                $valueFingerprint = Get-YamlEmissionNodeFingerprint -Node $entry.Value -Cache $Cache -Active $Active `
                    -Hasher $Hasher
                $entryFingerprint = Get-YamlFingerprintHash -Value "entry:$keyFingerprint=$valueFingerprint" `
                    -Hasher $Hasher
                $entries.Add($entryFingerprint)
            }
            $entries.Sort([System.StringComparer]::Ordinal)
            $fingerprint = Get-YamlFingerprintHash -Value ('mapping:{0}' -f ($entries -join '|')) -Hasher $Hasher
        }

        if ($hasReferenceId) {
            $Cache[$Node.ReferenceId] = $fingerprint
        }
        return $fingerprint
    } finally {
        if ($hasReferenceId) {
            [void] $Active.Remove($Node.ReferenceId)
        }
    }
}
