function ConvertTo-YamlNode {
    <#
        .SYNOPSIS
        Normalizes a supported PowerShell value to an emission node graph.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [pscustomobject] $State,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1024)]
        [int] $Depth,

        [switch] $EnumsAsStrings
    )

    if ($Depth -gt $State.MaxDepth) {
        throw (New-YamlSerializationException -ErrorId 'YamlDepthExceeded' -Message (
                "The object graph exceeds the configured depth limit of $($State.MaxDepth)."
            ))
    }

    $State.NodeCount++
    if ($State.NodeCount -gt $State.MaxNodes) {
        throw (New-YamlSerializationException -ErrorId 'YamlNodeLimitExceeded' -Message (
                "The object graph exceeds the configured limit of $($State.MaxNodes) nodes."
            ))
    }

    $scalar = New-YamlEmissionNode -Kind Scalar
    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        $scalar.Value = 'null'
        $scalar.Style = [YamlDotNet.Core.ScalarStyle]::Plain
        Confirm-YamlScalarLength -Node $scalar -State $State
        Write-Output -InputObject $scalar -NoEnumerate
        return
    }

    $dataProperties = @(
        $Value.PSObject.Properties |
            Where-Object {
                $_.IsInstance -and
                $_.MemberType -eq [System.Management.Automation.PSMemberTypes]::NoteProperty
            }
    )
    $unsupportedProperties = @(
        $Value.PSObject.Properties |
            Where-Object {
                $_.IsInstance -and $_.MemberType -in @(
                    [System.Management.Automation.PSMemberTypes]::AliasProperty,
                    [System.Management.Automation.PSMemberTypes]::CodeProperty,
                    [System.Management.Automation.PSMemberTypes]::ScriptProperty
                )
            }
    )
    $isPropertyBag = $Value -is [System.Management.Automation.PSCustomObject]
    $isPropertyBag = $isPropertyBag -or $dataProperties.Count -gt 0
    $isPropertyBag = $isPropertyBag -or $unsupportedProperties.Count -gt 0

    if ($unsupportedProperties.Count -gt 0) {
        throw (New-YamlSerializationException -Kind NotSupported -ErrorId 'YamlUnsupportedProperty' -Message (
                "Property '$($unsupportedProperties[0].Name)' is not a note property."
            ))
    }

    if (-not $isPropertyBag -and ($Value -is [string] -or $Value -is [char])) {
        $scalar.Value = [string] $Value
        $scalar.Style = [YamlDotNet.Core.ScalarStyle]::DoubleQuoted
        Confirm-YamlScalarLength -Node $scalar -State $State
        Write-Output -InputObject $scalar -NoEnumerate
        return
    }

    if (-not $isPropertyBag -and $Value -is [bool]) {
        $scalar.Value = $Value.ToString().ToLowerInvariant()
        $scalar.Style = [YamlDotNet.Core.ScalarStyle]::Plain
        Confirm-YamlScalarLength -Node $scalar -State $State
        Write-Output -InputObject $scalar -NoEnumerate
        return
    }

    if (-not $isPropertyBag -and $Value.GetType().IsEnum) {
        if ($EnumsAsStrings) {
            $scalar.Value = $Value.ToString()
            $scalar.Style = [YamlDotNet.Core.ScalarStyle]::DoubleQuoted
        } else {
            $underlyingType = [System.Enum]::GetUnderlyingType($Value.GetType())
            $numericValue = [System.Convert]::ChangeType(
                $Value,
                $underlyingType,
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            $scalar.Value = ([System.IConvertible] $numericValue).ToString(
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            $scalar.Style = [YamlDotNet.Core.ScalarStyle]::Plain
        }
        Confirm-YamlScalarLength -Node $scalar -State $State
        Write-Output -InputObject $scalar -NoEnumerate
        return
    }

    $integerTypes = @(
        [System.Byte],
        [System.SByte],
        [System.Int16],
        [System.UInt16],
        [System.Int32],
        [System.UInt32],
        [System.Int64],
        [System.UInt64],
        [System.Numerics.BigInteger]
    )
    if (-not $isPropertyBag -and $Value.GetType() -in $integerTypes) {
        if ($Value -is [System.Numerics.BigInteger]) {
            $scalar.Value = $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        } else {
            $scalar.Value = ([System.IConvertible] $Value).ToString(
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        }
        $scalar.Style = [YamlDotNet.Core.ScalarStyle]::Plain
        Confirm-YamlScalarLength -Node $scalar -State $State
        Write-Output -InputObject $scalar -NoEnumerate
        return
    }

    if (-not $isPropertyBag -and $Value -is [decimal]) {
        $scalar.Value = $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        if ($scalar.Value -notmatch '[\.eE]') {
            $scalar.Value += '.0'
        }
        $scalar.Style = [YamlDotNet.Core.ScalarStyle]::Plain
        Confirm-YamlScalarLength -Node $scalar -State $State
        Write-Output -InputObject $scalar -NoEnumerate
        return
    }

    if (-not $isPropertyBag -and ($Value -is [double] -or $Value -is [single])) {
        $number = [double] $Value
        if ([double]::IsNaN($number)) {
            $scalar.Value = '.nan'
        } elseif ([double]::IsPositiveInfinity($number)) {
            $scalar.Value = '.inf'
        } elseif ([double]::IsNegativeInfinity($number)) {
            $scalar.Value = '-.inf'
        } else {
            $scalar.Value = $number.ToString('R', [System.Globalization.CultureInfo]::InvariantCulture)
            if ($scalar.Value -notmatch '[\.eE]') {
                $scalar.Value += '.0'
            }
        }
        $scalar.Style = [YamlDotNet.Core.ScalarStyle]::Plain
        Confirm-YamlScalarLength -Node $scalar -State $State
        Write-Output -InputObject $scalar -NoEnumerate
        return
    }

    if (-not $isPropertyBag -and $Value -is [datetimeoffset]) {
        $scalar.Tag = 'tag:yaml.org,2002:timestamp'
        $scalar.Value = $Value.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        $scalar.Style = [YamlDotNet.Core.ScalarStyle]::DoubleQuoted
        Confirm-YamlScalarLength -Node $scalar -State $State
        Write-Output -InputObject $scalar -NoEnumerate
        return
    }

    if (-not $isPropertyBag -and $Value -is [datetime]) {
        $scalar.Tag = 'tag:yaml.org,2002:timestamp'
        if ($Value.Kind -eq [System.DateTimeKind]::Utc) {
            $scalar.Value = $Value.ToUniversalTime().ToString(
                "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        } elseif ($Value.Kind -eq [System.DateTimeKind]::Local) {
            $scalar.Value = ([datetimeoffset] $Value).ToString(
                'o',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        } else {
            $scalar.Value = $Value.ToString(
                "yyyy-MM-dd'T'HH:mm:ss.fffffff",
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        }
        $scalar.Style = [YamlDotNet.Core.ScalarStyle]::DoubleQuoted
        Confirm-YamlScalarLength -Node $scalar -State $State
        Write-Output -InputObject $scalar -NoEnumerate
        return
    }

    if (-not $isPropertyBag -and $Value -is [byte[]]) {
        $scalar.Tag = 'tag:yaml.org,2002:binary'
        $scalar.Value = [System.Convert]::ToBase64String($Value)
        $scalar.Style = [YamlDotNet.Core.ScalarStyle]::DoubleQuoted
        Confirm-YamlScalarLength -Node $scalar -State $State
        Write-Output -InputObject $scalar -NoEnumerate
        return
    }

    $isDictionary = $Value -is [System.Collections.IDictionary]
    $isCustomObject = $isPropertyBag
    $isSequence = $Value -is [System.Collections.IEnumerable]
    if (-not $isDictionary -and -not $isCustomObject -and -not $isSequence) {
        throw (New-YamlSerializationException -Kind NotSupported -ErrorId 'YamlUnsupportedType' -Message (
                "Values of type '$($Value.GetType().FullName)' are not supported for YAML serialization."
            ))
    }

    $firstTime = $false
    $referenceId = $State.IdGenerator.GetId($Value, [ref] $firstTime)
    if (-not $firstTime) {
        $State.ReferenceCounts[$referenceId]++
        if ($State.Active.Contains($referenceId)) {
            throw (New-YamlSerializationException -ErrorId 'YamlCycleDetected' -Message (
                    "A cycle was detected while serializing type '$($Value.GetType().FullName)'."
                ))
        }
        Write-Output -InputObject $State.NodesById[$referenceId] -NoEnumerate
        return
    }

    $State.ReferenceCounts[$referenceId] = 1
    $State.ReferenceOrder.Add($referenceId)
    [void] $State.Active.Add($referenceId)

    try {
        if ($isDictionary -or $isCustomObject) {
            $node = New-YamlEmissionNode -Kind Mapping
            $node.ReferenceId = $referenceId
            $State.NodesById[$referenceId] = $node
            $keyFingerprints = [System.Collections.Generic.HashSet[string]]::new(
                [System.StringComparer]::Ordinal
            )

            if ($isDictionary) {
                foreach ($entry in $Value.GetEnumerator()) {
                    $keyNode = ConvertTo-YamlNode -Value ([object] $entry.Key) -State $State -Depth ($Depth + 1) `
                        -EnumsAsStrings:$EnumsAsStrings
                    $keyFingerprint = Get-YamlEmissionNodeFingerprint -Node $keyNode -Cache $State.Fingerprints -Active (
                        [System.Collections.Generic.HashSet[long]]::new()
                    ) -Hasher $State.FingerprintHasher
                    if (-not $keyFingerprints.Add($keyFingerprint)) {
                        throw (New-YamlSerializationException -ErrorId 'YamlDuplicateKey' -Message (
                                'Two mapping keys normalize to the same YAML value.'
                            ))
                    }
                    $valueNode = ConvertTo-YamlNode -Value ([object] $entry.Value) -State $State -Depth ($Depth + 1) `
                        -EnumsAsStrings:$EnumsAsStrings
                    $node.Entries.Add([pscustomobject]@{
                            Key   = $keyNode
                            Value = $valueNode
                        })
                }
            } else {
                foreach ($property in $dataProperties) {
                    $keyNode = ConvertTo-YamlNode -Value ([object] $property.Name) -State $State -Depth ($Depth + 1) `
                        -EnumsAsStrings:$EnumsAsStrings
                    $keyFingerprint = Get-YamlEmissionNodeFingerprint -Node $keyNode -Cache $State.Fingerprints -Active (
                        [System.Collections.Generic.HashSet[long]]::new()
                    ) -Hasher $State.FingerprintHasher
                    if (-not $keyFingerprints.Add($keyFingerprint)) {
                        throw (New-YamlSerializationException -ErrorId 'YamlDuplicateKey' -Message (
                                'Two mapping keys normalize to the same YAML value.'
                            ))
                    }
                    $valueNode = ConvertTo-YamlNode -Value ([object] $property.Value) -State $State -Depth ($Depth + 1) `
                        -EnumsAsStrings:$EnumsAsStrings
                    $node.Entries.Add([pscustomobject]@{
                            Key   = $keyNode
                            Value = $valueNode
                        })
                }
            }
        } else {
            $node = New-YamlEmissionNode -Kind Sequence
            $node.ReferenceId = $referenceId
            $State.NodesById[$referenceId] = $node
            foreach ($item in $Value) {
                $itemNode = ConvertTo-YamlNode -Value ([object] $item) -State $State -Depth ($Depth + 1) `
                    -EnumsAsStrings:$EnumsAsStrings
                $node.Items.Add($itemNode)
            }
        }
    } finally {
        [void] $State.Active.Remove($referenceId)
    }

    Write-Output -InputObject $node -NoEnumerate
}
