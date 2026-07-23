function Get-YamlSerializationShape {
    <#
        .SYNOPSIS
        Classifies one PowerShell value for safe YAML graph normalization.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [pscustomobject] $State,

        [switch] $EnumsAsStrings
    )

    $scalar = New-YamlEmissionNode -Kind Scalar
    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        $scalar.Value = 'null'
        Confirm-YamlScalarLength -Node $scalar -State $State
        return [pscustomobject]@{ Kind = 'Scalar'; Node = $scalar; Values = $null }
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
    if ($unsupportedProperties.Count -gt 0) {
        throw (New-YamlSerializationException -Kind NotSupported `
                -ErrorId 'YamlUnsupportedProperty' -Message (
                "Property '$($unsupportedProperties[0].Name)' is not a note property."
            ))
    }

    $isDictionary = $Value -is [System.Collections.IDictionary]
    $isByteArray = $Value -is [byte[]]
    $isSequence = (
        $Value -is [System.Collections.IEnumerable] -and
        $Value -isnot [string] -and
        $Value -isnot [char] -and
        -not $isDictionary -and
        -not $isByteArray
    )
    $isCustomObject = $Value -is [System.Management.Automation.PSCustomObject]
    $isPurePropertyBag = $isCustomObject -or (
        $dataProperties.Count -gt 0 -and $Value.GetType() -eq [object]
    )
    if ($dataProperties.Count -gt 0 -and ($isDictionary -or $isSequence -or $isByteArray)) {
        throw (New-YamlSerializationException -Kind NotSupported `
                -ErrorId 'YamlMixedObjectSemantics' -Message (
                "Type '$($Value.GetType().FullName)' combines collection data with attached note properties and cannot be represented without loss."
            ))
    }
    if ($dataProperties.Count -gt 0 -and -not $isPurePropertyBag) {
        throw (New-YamlSerializationException -Kind NotSupported `
                -ErrorId 'YamlMixedObjectSemantics' -Message (
                "Type '$($Value.GetType().FullName)' combines scalar data with attached note properties and cannot be represented without loss."
            ))
    }
    $isPropertyBag = $isPurePropertyBag

    if (-not $isPropertyBag -and ($Value -is [string] -or $Value -is [char])) {
        $scalar.Value = [string] $Value
        $scalar.Style = 'DoubleQuoted'
        Confirm-YamlScalarLength -Node $scalar -State $State
        return [pscustomobject]@{ Kind = 'Scalar'; Node = $scalar; Values = $null }
    }
    if (-not $isPropertyBag -and $Value -is [bool]) {
        $scalar.Value = $Value.ToString().ToLowerInvariant()
        Confirm-YamlScalarLength -Node $scalar -State $State
        return [pscustomobject]@{ Kind = 'Scalar'; Node = $scalar; Values = $null }
    }
    if (-not $isPropertyBag -and $Value.GetType().IsEnum) {
        if ($EnumsAsStrings) {
            $scalar.Value = $Value.ToString()
            $scalar.Style = 'DoubleQuoted'
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
        }
        Confirm-YamlScalarLength -Node $scalar -State $State
        return [pscustomobject]@{ Kind = 'Scalar'; Node = $scalar; Values = $null }
    }

    $integerTypes = @(
        [System.Byte], [System.SByte], [System.Int16], [System.UInt16],
        [System.Int32], [System.UInt32], [System.Int64], [System.UInt64],
        [System.Numerics.BigInteger]
    )
    if (-not $isPropertyBag -and $Value.GetType() -in $integerTypes) {
        $scalar.Value = if ($Value -is [System.Numerics.BigInteger]) {
            $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        } else {
            ([System.IConvertible] $Value).ToString(
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        }
        Confirm-YamlScalarLength -Node $scalar -State $State
        return [pscustomobject]@{ Kind = 'Scalar'; Node = $scalar; Values = $null }
    }
    if (-not $isPropertyBag -and $Value -is [decimal]) {
        $bits = [decimal]::GetBits($Value)
        $negativeZero = $Value -eq 0 -and ($bits[3] -band [int]::MinValue) -ne 0
        $scalar.Value = if ($negativeZero) {
            '-0.0'
        } else {
            $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
        }
        if ($scalar.Value -notmatch '[\.eE]') {
            $scalar.Value += '.0'
        }
        Confirm-YamlScalarLength -Node $scalar -State $State
        return [pscustomobject]@{ Kind = 'Scalar'; Node = $scalar; Values = $null }
    }
    if (-not $isPropertyBag -and ($Value -is [double] -or $Value -is [single])) {
        $number = [double] $Value
        $scalar.Value = if ([double]::IsNaN($number)) {
            '.nan'
        } elseif ([double]::IsPositiveInfinity($number)) {
            '.inf'
        } elseif ([double]::IsNegativeInfinity($number)) {
            '-.inf'
        } elseif ($number -eq 0 -and
            [System.BitConverter]::DoubleToInt64Bits($number) -lt 0) {
            '-0.0'
        } else {
            $formatted = $number.ToString(
                'R',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
            if ($formatted -notmatch '[\.eE]') {
                $formatted += '.0'
            }
            $formatted
        }
        Confirm-YamlScalarLength -Node $scalar -State $State
        return [pscustomobject]@{ Kind = 'Scalar'; Node = $scalar; Values = $null }
    }
    if (-not $isPropertyBag -and $Value -is [datetimeoffset]) {
        $scalar.Tag = 'tag:yaml.org,2002:timestamp'
        $scalar.Value = $Value.ToString('o', [System.Globalization.CultureInfo]::InvariantCulture)
        $scalar.Style = 'DoubleQuoted'
        Confirm-YamlScalarLength -Node $scalar -State $State
        return [pscustomobject]@{ Kind = 'Scalar'; Node = $scalar; Values = $null }
    }
    if (-not $isPropertyBag -and $Value -is [datetime]) {
        $scalar.Tag = 'tag:yaml.org,2002:timestamp'
        if ($Value.Kind -eq [System.DateTimeKind]::Local) {
            $scalar.Value = ([datetimeoffset] $Value).ToString(
                'o',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        } else {
            $utc = if ($Value.Kind -eq [System.DateTimeKind]::Utc) {
                $Value
            } else {
                [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
            }
            $scalar.Value = $utc.ToString(
                "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        }
        $scalar.Style = 'DoubleQuoted'
        Confirm-YamlScalarLength -Node $scalar -State $State
        return [pscustomobject]@{ Kind = 'Scalar'; Node = $scalar; Values = $null }
    }

    if ($isByteArray) {
        $scalar.Tag = 'tag:yaml.org,2002:binary'
        $scalar.Value = [System.Convert]::ToBase64String($Value)
        $scalar.Style = 'DoubleQuoted'
        Confirm-YamlScalarLength -Node $scalar -State $State
        return [pscustomobject]@{ Kind = 'Binary'; Node = $scalar; Values = $null }
    }

    if ($isDictionary -or $isPropertyBag) {
        $entries = [System.Collections.Generic.List[object]]::new()
        if ($isDictionary) {
            foreach ($entry in $Value.GetEnumerator()) {
                $entries.Add([pscustomobject]@{
                        Key   = [object] $entry.Key
                        Value = [object] $entry.Value
                    })
            }
        } else {
            foreach ($property in $dataProperties) {
                $entries.Add([pscustomobject]@{
                        Key   = [object] $property.Name
                        Value = [object] $property.Value
                    })
            }
        }
        return [pscustomobject]@{
            Kind   = 'Mapping'
            Node   = $null
            Values = [object[]] $entries.ToArray()
        }
    }
    if ($isSequence) {
        $items = [System.Collections.Generic.List[object]]::new()
        foreach ($item in $Value) {
            $items.Add([object] $item)
        }
        return [pscustomobject]@{
            Kind   = 'Sequence'
            Node   = $null
            Values = [object[]] $items.ToArray()
        }
    }

    throw (New-YamlSerializationException -Kind NotSupported `
            -ErrorId 'YamlUnsupportedType' -Message (
            "Values of type '$($Value.GetType().FullName)' are not supported for YAML serialization."
        ))
}
