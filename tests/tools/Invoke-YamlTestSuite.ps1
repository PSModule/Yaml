[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSProvideCommentHelp', '',
    Justification = 'Internal test helper functions in this tooling script.'
)]
[CmdletBinding()]
param (
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -LiteralPath $_ -PathType Container })]
    [string] $Path,

    [switch] $CompareJson,
    [switch] $CompareEvents,
    [switch] $CompareOutYaml,
    [switch] $CompareEmitYaml,
    [switch] $CompareSelfRoundTrip
)

. (Join-Path $PSScriptRoot '..\TestBootstrap.ps1')

if (-not $PSBoundParameters.ContainsKey('CompareJson') -and
    -not $PSBoundParameters.ContainsKey('CompareEvents') -and
    -not $PSBoundParameters.ContainsKey('CompareOutYaml') -and
    -not $PSBoundParameters.ContainsKey('CompareEmitYaml') -and
    -not $PSBoundParameters.ContainsKey('CompareSelfRoundTrip')) {
    $CompareJson = $true
    $CompareEvents = $true
    $CompareOutYaml = $true
    $CompareEmitYaml = $true
    $CompareSelfRoundTrip = $true
}

function Invoke-InYamlModule {
    param (
        [Parameter(Mandatory)]
        [scriptblock] $ScriptBlock,

        [AllowNull()]
        [object[]] $Arguments = @()
    )

    if ($null -eq $yamlModule) {
        return & $ScriptBlock @Arguments
    }

    return & $yamlModule $ScriptBlock @Arguments
}

function Split-YamlSuiteJsonDocument {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $documents = [System.Collections.Generic.List[string]]::new()
    $index = 0
    while ($index -lt $Text.Length) {
        while ($index -lt $Text.Length -and [char]::IsWhiteSpace($Text[$index])) {
            $index++
        }
        if ($index -ge $Text.Length) {
            break
        }

        $start = $index
        $first = $Text[$index]
        if ($first -eq '{' -or $first -eq '[') {
            $depth = 0
            $quoted = $false
            $escaped = $false
            while ($index -lt $Text.Length) {
                $character = $Text[$index++]
                if ($quoted) {
                    if ($escaped) {
                        $escaped = $false
                    } elseif ($character -eq '\') {
                        $escaped = $true
                    } elseif ($character -eq '"') {
                        $quoted = $false
                    }
                    continue
                }
                if ($character -eq '"') {
                    $quoted = $true
                } elseif ($character -eq '{' -or $character -eq '[') {
                    $depth++
                } elseif ($character -eq '}' -or $character -eq ']') {
                    $depth--
                    if ($depth -eq 0) {
                        break
                    }
                }
            }
        } elseif ($first -eq '"') {
            $index++
            $escaped = $false
            while ($index -lt $Text.Length) {
                $character = $Text[$index++]
                if ($escaped) {
                    $escaped = $false
                } elseif ($character -eq '\') {
                    $escaped = $true
                } elseif ($character -eq '"') {
                    break
                }
            }
        } else {
            while ($index -lt $Text.Length -and -not [char]::IsWhiteSpace($Text[$index])) {
                $index++
            }
        }
        $documents.Add($Text.Substring($start, $index - $start))
    }

    [string[]] $documents.ToArray()
}

function ConvertTo-YamlSuiteCanonicalValue {
    param (
        [AllowNull()]
        [object] $Value,

        [switch] $SortMappings
    )

    if ($null -eq $Value -or $Value -is [System.DBNull]) {
        return 'null'
    }
    if ($Value -is [string]) {
        return 'string:{0}:{1}' -f $Value.Length, $Value
    }
    if ($Value -is [bool]) {
        return 'bool:{0}' -f $Value.ToString().ToLowerInvariant()
    }
    if ($Value -is [byte[]]) {
        return 'binary:{0}:{1}' -f $Value.Length, [System.Convert]::ToBase64String($Value)
    }
    if ($Value -is [char]) {
        return 'char:{0}' -f [int] $Value
    }
    if ($Value.GetType().IsEnum) {
        return 'enum:{0}:{1}' -f $Value.GetType().FullName, (
            [System.Convert]::ToUInt64($Value, [cultureinfo]::InvariantCulture)
        )
    }
    if ($Value -is [datetimeoffset]) {
        return 'timestamp:{0}:{1}' -f $Value.UtcTicks, $Value.Offset.Ticks
    }
    if ($Value -is [datetime]) {
        return 'datetime:{0}:{1}' -f $Value.Ticks, [int] $Value.Kind
    }
    if ($Value -is [timespan]) {
        return 'timespan:{0}' -f $Value.Ticks
    }
    if ($Value -is [guid]) {
        return 'guid:{0}' -f $Value.ToString('D')
    }
    if ($Value -is [uri]) {
        return 'uri:{0}:{1}' -f $Value.OriginalString.Length, $Value.OriginalString
    }

    $typeCode = [System.Type]::GetTypeCode($Value.GetType())
    if ($Value -is [System.Numerics.BigInteger] -or $typeCode -in @(
            [System.TypeCode]::SByte,
            [System.TypeCode]::Byte,
            [System.TypeCode]::Int16,
            [System.TypeCode]::UInt16,
            [System.TypeCode]::Int32,
            [System.TypeCode]::UInt32,
            [System.TypeCode]::Int64,
            [System.TypeCode]::UInt64
        )) {
        return 'number:{0}' -f $Value.ToString([cultureinfo]::InvariantCulture)
    }
    if ($Value -is [decimal]) {
        return 'number:{0}' -f $Value.ToString('G29', [cultureinfo]::InvariantCulture)
    }
    if ($Value -is [single] -or $Value -is [double]) {
        return 'number:{0}' -f ([double] $Value).ToString('R', [cultureinfo]::InvariantCulture)
    }
    if ($Value -is [System.Collections.IDictionary]) {
        $entries = [System.Collections.Generic.List[string]]::new()
        foreach ($entry in $Value.GetEnumerator()) {
            $canonicalKey = ConvertTo-YamlSuiteCanonicalValue -Value $entry.Key `
                -SortMappings:$SortMappings
            $canonicalValue = ConvertTo-YamlSuiteCanonicalValue -Value $entry.Value `
                -SortMappings:$SortMappings
            $entries.Add(('{0}:{1}={2}:{3}' -f
                    $canonicalKey.Length,
                    $canonicalKey,
                    $canonicalValue.Length,
                    $canonicalValue
                ))
        }
        $isOrdered = (
            $Value -is [System.Collections.Specialized.OrderedDictionary] -or
            $Value.GetType().FullName -ceq 'System.Management.Automation.OrderedHashtable'
        )
        if ($SortMappings -or -not $isOrdered) {
            $entries.Sort([System.StringComparer]::Ordinal)
        }
        return 'map:{0}:{{{1}}}' -f $entries.Count, ($entries -join '|')
    }
    if ($Value -is [System.Collections.IEnumerable] -and $Value -isnot [string]) {
        $items = [System.Collections.Generic.List[string]]::new()
        foreach ($item in $Value) {
            $items.Add((
                    ConvertTo-YamlSuiteCanonicalValue -Value $item -SortMappings:$SortMappings
                ))
        }
        return 'sequence:{0}:[{1}]' -f $items.Count, ($items -join '|')
    }

    $serialized = [System.Management.Automation.PSSerializer]::Serialize($Value, 3)
    $payload = [System.Convert]::ToBase64String(
        [System.Text.Encoding]::UTF8.GetBytes($serialized)
    )
    if (-not $Value.GetType().IsValueType) {
        return 'unsupported-reference:{0}:{1}:{2}' -f
        $Value.GetType().FullName,
        [System.Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Value),
        $payload
    }
    return 'unsupported-value:{0}:{1}' -f $Value.GetType().FullName, $payload
}

function ConvertTo-YamlSuiteReferenceSignature {
    [OutputType([string])]
    param (
        [AllowNull()]
        [object] $Value
    )

    $idGenerator = [System.Runtime.Serialization.ObjectIDGenerator]::new()
    $pathsById = [System.Collections.Generic.Dictionary[long, object]]::new()
    $typesById = [System.Collections.Generic.Dictionary[long, string]]::new()
    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{ Value = $Value; Path = '$' })

    while ($stack.Count -gt 0) {
        $frame = $stack.Pop()
        $current = $frame.Value
        if ($null -eq $current -or $current -is [string]) {
            continue
        }
        if ($current -isnot [System.Collections.IDictionary] -and
            ($current -isnot [System.Collections.IEnumerable])) {
            continue
        }

        $first = $false
        $id = $idGenerator.GetId($current, [ref] $first)
        if (-not $pathsById.ContainsKey($id)) {
            $pathsById[$id] = [System.Collections.Generic.List[string]]::new()
            $typesById[$id] = $current.GetType().FullName
        }
        $pathsById[$id].Add($frame.Path)
        if (-not $first) {
            continue
        }
        if ($current -is [byte[]]) {
            continue
        }

        if ($current -is [System.Collections.IDictionary]) {
            foreach ($entry in $current.GetEnumerator()) {
                $childPath = '{0}{{{1}}}' -f $frame.Path, (
                    ConvertTo-YamlSuiteCanonicalValue -Value $entry.Key
                )
                $stack.Push([pscustomobject]@{
                        Value = $entry.Value
                        Path  = "$childPath.value"
                    })
                $stack.Push([pscustomobject]@{
                        Value = $entry.Key
                        Path  = "$childPath.key"
                    })
            }
            continue
        }

        $index = 0
        foreach ($item in $current) {
            $stack.Push([pscustomobject]@{
                    Value = $item
                    Path  = ('{0}[{1}]' -f $frame.Path, $index)
                })
            $index++
        }
    }

    $parts = [System.Collections.Generic.List[string]]::new()
    foreach ($id in $pathsById.Keys) {
        $paths = $pathsById[$id]
        if ($paths.Count -gt 1) {
            $sorted = [string[]] $paths.ToArray()
            [array]::Sort($sorted, [System.StringComparer]::Ordinal)
            $parts.Add(('{0}|{1}|{2}' -f $typesById[$id], $paths.Count, ($sorted -join ',')))
        }
    }
    $output = [string[]] $parts.ToArray()
    [array]::Sort($output, [System.StringComparer]::Ordinal)
    return ($output -join ';')
}

function Test-YamlSuiteBinaryByteArrayProjection {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [object[]] $ExpectedValues,

        [Parameter(Mandatory)]
        [object[]] $ActualValues
    )

    if ($ExpectedValues.Count -ne 1 -or $ActualValues.Count -ne 1) {
        return $false
    }
    $expectedDocument = $ExpectedValues[0]
    $actualDocument = $ActualValues[0]
    if ($expectedDocument -isnot [System.Collections.IDictionary] -or
        $actualDocument -isnot [System.Collections.IDictionary] -or
        $expectedDocument.Count -ne 3 -or $actualDocument.Count -ne 3) {
        return $false
    }

    foreach ($key in @('canonical', 'generic', 'description')) {
        if (-not $expectedDocument.Contains($key) -or -not $actualDocument.Contains($key)) {
            return $false
        }
    }
    if ($expectedDocument['description'] -isnot [string] -or
        $actualDocument['description'] -isnot [string] -or
        $actualDocument['description'] -cne $expectedDocument['description']) {
        return $false
    }

    foreach ($key in @('canonical', 'generic')) {
        if ($expectedDocument[$key] -isnot [string] -or
            $actualDocument[$key] -isnot [byte[]]) {
            return $false
        }
        $expectedBase64 = $expectedDocument[$key] -replace '\s', ''
        $expectedBytes = [System.Convert]::FromBase64String($expectedBase64)
        if (-not [System.Linq.Enumerable]::SequenceEqual[byte](
                $expectedBytes,
                [byte[]] $actualDocument[$key]
            )) {
            return $false
        }
    }
    return $true
}

function Test-YamlSuiteLegacyOrderedMapProjection {
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [object[]] $ExpectedValues,

        [Parameter(Mandatory)]
        [object[]] $ActualValues
    )

    if ($ExpectedValues.Count -ne 1 -or $ActualValues.Count -ne 1 -or
        $ExpectedValues[0] -is [System.Collections.IDictionary] -or
        $ExpectedValues[0] -isnot [System.Collections.IEnumerable] -or
        $ActualValues[0] -isnot [System.Collections.Specialized.OrderedDictionary]) {
        return $false
    }

    $expectedEntries = @($ExpectedValues[0])
    $actualDocument = $ActualValues[0]
    $actualKeys = @($actualDocument.Keys)
    if ($expectedEntries.Count -ne $actualDocument.Count) {
        return $false
    }
    for ($index = 0; $index -lt $expectedEntries.Count; $index++) {
        $expectedEntry = $expectedEntries[$index]
        if ($expectedEntry -isnot [System.Collections.IDictionary] -or
            $expectedEntry.Count -ne 1) {
            return $false
        }
        $expectedKey = @($expectedEntry.Keys)[0]
        if ($expectedKey -isnot [string] -or $actualKeys[$index] -cne $expectedKey -or
            (ConvertTo-YamlSuiteCanonicalValue -Value $actualDocument[$expectedKey]) -cne
            (ConvertTo-YamlSuiteCanonicalValue -Value $expectedEntry[$expectedKey])) {
            return $false
        }
    }
    return $true
}

function Get-YamlSuiteJsonPolicyReason {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object[]] $ExpectedValues,

        [Parameter(Mandatory)]
        [object[]] $ActualValues
    )

    if (Test-YamlSuiteBinaryByteArrayProjection -ExpectedValues $ExpectedValues `
            -ActualValues $ActualValues) {
        return 'BinaryByteArrayProjection'
    }
    if (Test-YamlSuiteLegacyOrderedMapProjection -ExpectedValues $ExpectedValues `
            -ActualValues $ActualValues) {
        return 'LegacyOrderedMapProjection'
    }
    return ''
    return ''
}

function ConvertFrom-YamlSuiteEventText {
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [string] $Text
    )

    function ConvertTo-YamlSuiteEventEscapedText {
        param ([AllowNull()][string] $Value)
        if ($null -eq $Value) {
            return ''
        }
        $builder = [System.Text.StringBuilder]::new()
        foreach ($character in $Value.ToCharArray()) {
            switch ($character) {
                '\' { [void] $builder.Append('\\') }
                "`n" { [void] $builder.Append('\n') }
                "`r" { [void] $builder.Append('\r') }
                "`t" { [void] $builder.Append('\t') }
                default { [void] $builder.Append($character) }
            }
        }
        $builder.ToString()
    }

    function ConvertFrom-YamlSuiteEventEscape {
        param ([AllowNull()][string] $Value)
        if ($null -eq $Value) {
            return ''
        }
        $builder = [System.Text.StringBuilder]::new()
        $index = 0
        while ($index -lt $Value.Length) {
            $current = $Value[$index]
            if ($current -eq '\' -and $index + 1 -lt $Value.Length) {
                $index++
                switch ($Value[$index]) {
                    'n' { [void] $builder.Append("`n") }
                    'r' { [void] $builder.Append("`r") }
                    't' { [void] $builder.Append("`t") }
                    'b' { [void] $builder.Append("`b") }
                    '\' { [void] $builder.Append('\') }
                    default {
                        [void] $builder.Append($Value[$index])
                    }
                }
                $index++
                continue
            }
            [void] $builder.Append($current)
            $index++
        }
        $builder.ToString()
    }

    $anchorMap = [System.Collections.Generic.Dictionary[string, string]]::new([System.StringComparer]::Ordinal)
    $anchorCounter = 0
    $canonical = [System.Collections.Generic.List[string]]::new()
    $lines = $Text -split '\r?\n'

    foreach ($rawLine in $lines) {
        $line = $rawLine
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        if ($line -in @('+STR', '-STR', '+DOC', '-DOC', '+DOC ---', '-DOC ...')) {
            $canonical.Add($line.Substring(0, 4))
            continue
        }
        if ($line -eq '-SEQ' -or $line -eq '-MAP') {
            $canonical.Add($line)
            continue
        }

        if ($line.StartsWith('+SEQ', [System.StringComparison]::Ordinal) -or
            $line.StartsWith('+MAP', [System.StringComparison]::Ordinal) -or
            $line.StartsWith('=VAL', [System.StringComparison]::Ordinal)) {
            $prefix = $line.Substring(0, 4)
            $rest = if ($line.Length -gt 4) { $line.Substring(4).TrimStart() } else { '' }
            $anchor = ''
            $tag = ''
            $value = ''
            $style = ''

            while ($rest.Length -gt 0) {
                if ($rest.StartsWith('[]', [System.StringComparison]::Ordinal) -or
                    $rest.StartsWith('{}', [System.StringComparison]::Ordinal)) {
                    $rest = $rest.Substring(2).TrimStart()
                    continue
                }
                if ($rest[0] -eq '&') {
                    $space = $rest.IndexOf(' ')
                    if ($space -lt 0) {
                        $anchor = $rest.Substring(1)
                        $rest = ''
                    } else {
                        $anchor = $rest.Substring(1, $space - 1)
                        $rest = $rest.Substring($space + 1).TrimStart()
                    }
                    continue
                }
                if ($rest[0] -eq '<') {
                    $end = $rest.IndexOf('>')
                    if ($end -ge 0) {
                        $tag = $rest.Substring(1, $end - 1)
                        $rest = $rest.Substring($end + 1).TrimStart()
                        continue
                    }
                }
                break
            }

            if ($prefix -eq '=VAL') {
                if ($rest.Length -gt 0 -and
                    ($rest[0] -eq ':' -or $rest[0] -eq '"' -or $rest[0] -eq "'" -or
                    $rest[0] -eq '|' -or $rest[0] -eq '>')) {
                    $style = [string] $rest[0]
                    $value = $rest.Substring(1)
                } else {
                    $value = $rest
                }
                if ($style -in @('|', '>') -and [string]::IsNullOrEmpty($value)) {
                    $value = ''
                }
                $value = ConvertTo-YamlSuiteEventEscapedText -Value (
                    ConvertFrom-YamlSuiteEventEscape -Value $value
                )
            }

            $anchorToken = ''
            if ($anchor) {
                if (-not $anchorMap.ContainsKey($anchor)) {
                    $anchorCounter++
                    $anchorMap[$anchor] = 'a{0:d3}' -f $anchorCounter
                }
                $anchorToken = $anchorMap[$anchor]
            }
            $parts = [System.Collections.Generic.List[string]]::new()
            $parts.Add($prefix)
            if ($tag -and $tag -ne '!') { $parts.Add("tag=$tag") }
            if ($anchorToken) { $parts.Add("anchor=$anchorToken") }
            if ($prefix -eq '=VAL') { $parts.Add("value=$value") }
            $canonical.Add(($parts -join '|'))
            continue
        }

        if ($line.StartsWith('=ALI', [System.StringComparison]::Ordinal)) {
            $alias = $line.Substring(4).Trim()
            if ($alias.StartsWith('*', [System.StringComparison]::Ordinal)) {
                $alias = $alias.Substring(1)
            }
            if (-not $anchorMap.ContainsKey($alias)) {
                $anchorCounter++
                $anchorMap[$alias] = 'a{0:d3}' -f $anchorCounter
            }
            $canonical.Add(('=ALI|target={0}' -f $anchorMap[$alias]))
            continue
        }

        $canonical.Add("UNKNOWN|$line")
    }

    [string[]] $canonical.ToArray()
}

function ConvertTo-YamlSuiteActualEvent {
    [OutputType([string[]])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]] $Documents
    )

    function ConvertTo-YamlSuiteEventEscapedText {
        param ([AllowNull()][string] $Value)
        if ($null -eq $Value) {
            return ''
        }
        $builder = [System.Text.StringBuilder]::new()
        foreach ($character in $Value.ToCharArray()) {
            switch ($character) {
                '\' { [void] $builder.Append('\\') }
                "`n" { [void] $builder.Append('\n') }
                "`r" { [void] $builder.Append('\r') }
                "`t" { [void] $builder.Append('\t') }
                default { [void] $builder.Append($character) }
            }
        }
        $builder.ToString()
    }

    $anchorMap = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::Ordinal
    )
    $anchorCounter = 0
    $events = [System.Collections.Generic.List[string]]::new()
    $events.Add('+STR')

    foreach ($document in $Documents) {
        $events.Add('+DOC')
        $stack = [System.Collections.Generic.Stack[object]]::new()
        $stack.Push([pscustomobject]@{ Type = 'Node'; Node = $document })

        while ($stack.Count -gt 0) {
            $frame = $stack.Pop()
            if ($frame.Type -eq 'End') {
                $events.Add($frame.Value)
                continue
            }

            $node = $frame.Node
            if ($node.Kind -eq 'Alias') {
                $targetAnchorKey = if ([string]::IsNullOrEmpty($node.Target.Anchor)) {
                    'id:{0}' -f $node.Target.Id
                } else {
                    $node.Target.Anchor
                }
                $targetAnchor = Get-YamlSuiteAnchorToken -Key $targetAnchorKey `
                    -AnchorMap $anchorMap -AnchorCounter ([ref] $anchorCounter)
                $events.Add("=ALI|target=$targetAnchor")
                continue
            }
            if ($node.Kind -eq 'Scalar') {
                $parts = [System.Collections.Generic.List[string]]::new()
                $parts.Add('=VAL')
                if ($node.Tag -and $node.Tag -ne '!') { $parts.Add("tag=$($node.Tag)") }
                if ($node.Anchor) {
                    $parts.Add("anchor=$(
                            Get-YamlSuiteAnchorToken -Key $node.Anchor -AnchorMap $anchorMap `
                                -AnchorCounter ([ref] $anchorCounter)
                        )")
                }
                $parts.Add(("value={0}" -f (
                            ConvertTo-YamlSuiteEventEscapedText -Value ([string] $node.Value)
                        )))
                $events.Add(($parts -join '|'))
                continue
            }

            $startParts = [System.Collections.Generic.List[string]]::new()
            $startToken = if ($node.Kind -eq 'Sequence') { '+SEQ' } else { '+MAP' }
            $startParts.Add($startToken)
            if ($node.Tag -and $node.Tag -ne '!') { $startParts.Add("tag=$($node.Tag)") }
            if ($node.Anchor) {
                $startParts.Add("anchor=$(
                        Get-YamlSuiteAnchorToken -Key $node.Anchor -AnchorMap $anchorMap `
                            -AnchorCounter ([ref] $anchorCounter)
                    )")
            }
            $events.Add(($startParts -join '|'))

            if ($node.Kind -eq 'Sequence') {
                $stack.Push([pscustomobject]@{ Type = 'End'; Value = '-SEQ' })
                for ($index = $node.Items.Count - 1; $index -ge 0; $index--) {
                    $stack.Push([pscustomobject]@{ Type = 'Node'; Node = $node.Items[$index] })
                }
            } else {
                $stack.Push([pscustomobject]@{ Type = 'End'; Value = '-MAP' })
                for ($index = $node.Entries.Count - 1; $index -ge 0; $index--) {
                    $stack.Push([pscustomobject]@{ Type = 'Node'; Node = $node.Entries[$index].Value })
                    $stack.Push([pscustomobject]@{ Type = 'Node'; Node = $node.Entries[$index].Key })
                }
            }
        }
        $events.Add('-DOC')
    }

    $events.Add('-STR')
    [string[]] $events.ToArray()
}

function Compare-YamlSuiteCanonicalList {
    [OutputType([bool])]
    param (
        [string[]] $Left,
        [string[]] $Right
    )

    if ($Left.Length -ne $Right.Length) {
        return $false
    }
    for ($index = 0; $index -lt $Left.Length; $index++) {
        if ($Left[$index] -cne $Right[$index]) {
            return $false
        }
    }
    return $true
}

function Get-YamlSuiteAnchorToken {
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string] $Key,

        [Parameter(Mandatory)]
        [System.Collections.Generic.Dictionary[string, string]] $AnchorMap,

        [Parameter(Mandatory)]
        [ref] $AnchorCounter
    )

    if (-not $AnchorMap.ContainsKey($Key)) {
        $AnchorCounter.Value++
        $AnchorMap[$Key] = 'a{0:d3}' -f $AnchorCounter.Value
    }
    $AnchorMap[$Key]
}

$readYamlSuiteRepresentation = {
    param ([string] $YamlText)
    Read-YamlStreamCore -Yaml $YamlText -Depth 128 -MaxNodes 100000 `
        -MaxAliases 1000 -MaxScalarLength 1048576 -MaxTagLength 1024 `
        -MaxTotalTagLength 65536 -MaxNumericLength 4096 -SkipGraphValidation
}
$readYamlSuiteStream = {
    param ([string] $YamlText)
    Read-YamlStream -Yaml $YamlText -Depth 128 -MaxNodes 100000 `
        -MaxAliases 1000 -MaxScalarLength 1048576 -MaxTagLength 1024 `
        -MaxTotalTagLength 65536 -MaxNumericLength 4096
}
$projectYamlSuiteStream = {
    param ([object[]] $Nodes)
    $values = [System.Collections.Generic.List[object]]::new()
    foreach ($node in $Nodes) {
        $cache = [System.Collections.Generic.Dictionary[int, object]]::new()
        $values.Add((ConvertFrom-YamlNode -Node $node -Cache $cache -AsHashtable).Value)
    }
    New-YamlValueBox -Value ([object[]] $values.ToArray())
}
$projectYamlSuiteText = {
    param ([string] $YamlText)

    $stream = Read-YamlStream -Yaml $YamlText -Depth 128 -MaxNodes 100000 `
        -MaxAliases 1000 -MaxScalarLength 1048576 -MaxTagLength 1024 `
        -MaxTotalTagLength 65536 -MaxNumericLength 4096
    $values = [System.Collections.Generic.List[object]]::new()
    foreach ($node in $stream.Value) {
        $cache = [System.Collections.Generic.Dictionary[int, object]]::new()
        $values.Add((ConvertFrom-YamlNode -Node $node -Cache $cache -AsHashtable).Value)
    }
    New-YamlValueBox -Value ([object[]] $values.ToArray())
}
$testYamlSuiteText = {
    param ([string] $YamlText)
    Test-Yaml -Yaml $YamlText -Depth 128 -MaxNodes 100000 -MaxAliases 1000 `
        -MaxScalarLength 1048576 -MaxTagLength 1024 -MaxTotalTagLength 65536 `
        -MaxNumericLength 4096
}

$suiteRoot = (Resolve-Path -LiteralPath $Path).Path
$inputFiles = @(
    Get-ChildItem -LiteralPath $suiteRoot -Recurse -File -Filter 'in.yaml' |
        Sort-Object FullName
)

foreach ($inputFile in $inputFiles) {
    $casePath = $inputFile.DirectoryName.Substring($suiteRoot.Length).TrimStart(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar
    ).Replace([System.IO.Path]::DirectorySeparatorChar, '/')
    $yaml = [System.IO.File]::ReadAllText(
        $inputFile.FullName,
        [System.Text.UTF8Encoding]::new($false, $true)
    )

    $errorPath = Join-Path $inputFile.DirectoryName 'error'
    $jsonPath = Join-Path $inputFile.DirectoryName 'in.json'
    $eventPath = Join-Path $inputFile.DirectoryName 'test.event'
    $outYamlPath = Join-Path $inputFile.DirectoryName 'out.yaml'
    $emitYamlPath = Join-Path $inputFile.DirectoryName 'emit.yaml'

    $expectsError = Test-Path -LiteralPath $errorPath -PathType Leaf
    $hasJson = Test-Path -LiteralPath $jsonPath -PathType Leaf
    $hasEvent = Test-Path -LiteralPath $eventPath -PathType Leaf
    $hasOutYaml = Test-Path -LiteralPath $outYamlPath -PathType Leaf
    $hasEmitYaml = Test-Path -LiteralPath $emitYamlPath -PathType Leaf

    $syntaxResult = 'Pass'
    $syntaxReason = ''
    $eventResult = 'NotApplicable'
    $eventReason = ''
    $jsonResult = 'NotApplicable'
    $jsonReason = ''
    $outYamlResult = 'NotApplicable'
    $outYamlReason = ''
    $emitYamlResult = 'NotApplicable'
    $emitYamlReason = ''
    $selfRoundTripResult = 'NotApplicable'
    $selfRoundTripReason = ''

    $representation = $null
    $stream = $null
    $projectedValues = $null
    $projectedCanonical = $null
    $projectedJsonCanonical = $null
    $projectedReference = ''
    $projectionError = ''
    $eventExpected = $null
    $eventActual = $null
    $jsonExpected = $null
    $jsonActual = $null
    $outYamlCanonical = $null
    $outYamlReference = $null
    $emitYamlExpected = $null
    $emitYamlActual = $null
    $emitYamlExpectedReference = $null
    $emitYamlActualReference = $null
    $selfRoundTripCanonical = $null
    $selfRoundTripReference = $null

    try {
        $representation = Invoke-InYamlModule -ScriptBlock $readYamlSuiteRepresentation -Arguments @($yaml)
    } catch {
        if (-not $_.Exception.Data.Contains('IsYamlException')) {
            throw
        }
        if ($expectsError) {
            $syntaxResult = 'Pass'
        } else {
            $syntaxResult = 'Fail'
            $syntaxReason = [string] $_.Exception.Data['YamlErrorId']
        }
    }

    if ($syntaxResult -ne 'Fail') {
        try {
            $stream = Invoke-InYamlModule -ScriptBlock $readYamlSuiteStream -Arguments @($yaml)
            if ($expectsError) {
                $syntaxResult = 'Fail'
                $syntaxReason = 'InvalidInputAccepted'
            }
        } catch {
            if (-not $_.Exception.Data.Contains('IsYamlException')) {
                throw
            }
            if ($expectsError) {
                $syntaxResult = 'Pass'
            } elseif ($casePath -cin @('2JQS', 'X38W') -and
                $_.Exception.Data['YamlErrorId'] -eq 'YamlDuplicateKey') {
                $syntaxResult = 'PolicyDifference'
                $syntaxReason = 'RepresentationMappingKeyUniqueness'
            } else {
                $syntaxResult = 'Fail'
                $syntaxReason = [string] $_.Exception.Data['YamlErrorId']
            }
        }
    }

    if ($null -ne $stream) {
        try {
            $projectedValues = (Invoke-InYamlModule -ScriptBlock $projectYamlSuiteStream -Arguments (, $stream.Value)).Value
            $projectedCanonical = ConvertTo-YamlSuiteCanonicalValue -Value ([object[]] $projectedValues)
            $projectedJsonCanonical = ConvertTo-YamlSuiteCanonicalValue `
                -Value ([object[]] $projectedValues) -SortMappings
            $projectedReference = ConvertTo-YamlSuiteReferenceSignature -Value ([object[]] $projectedValues)
        } catch {
            if ($_.Exception.Data.Contains('YamlErrorId')) {
                $projectionError = [string] $_.Exception.Data['YamlErrorId']
            } else {
                $projectionError = $_.Exception.GetType().Name
            }
        }
    }

    if ($CompareEvents -and $hasEvent) {
        if ($null -eq $representation -or $expectsError) {
            $eventResult = 'NotApplicable'
            if ($expectsError) { $eventReason = 'InvalidSyntax' }
        } else {
            $expectedEvents = ConvertFrom-YamlSuiteEventText -Text (
                [System.IO.File]::ReadAllText($eventPath, [System.Text.UTF8Encoding]::new($false, $true))
            )
            $actualEvents = ConvertTo-YamlSuiteActualEvent -Documents $representation.Value
            $eventExpected = ($expectedEvents -join "`n")
            $eventActual = ($actualEvents -join "`n")
            if (Compare-YamlSuiteCanonicalList -Left $actualEvents -Right $expectedEvents) {
                $eventResult = 'Pass'
            } else {
                $eventResult = 'Fail'
                $eventReason = 'EventMismatch'
            }
        }
    }

    if ($CompareJson -and $hasJson) {
        if ($null -eq $stream -or $expectsError -or $syntaxResult -eq 'PolicyDifference' -or
            $null -eq $projectedValues) {
            $jsonResult = 'NotApplicable'
            if ($syntaxResult -eq 'PolicyDifference') { $jsonReason = $syntaxReason }
            if ($projectionError) { $jsonReason = $projectionError }
        } else {
            $expectedDocuments = Split-YamlSuiteJsonDocument -Text (
                [System.IO.File]::ReadAllText($jsonPath, [System.Text.UTF8Encoding]::new($false, $true))
            )
            $expectedValues = [System.Collections.Generic.List[object]]::new()
            foreach ($document in $expectedDocuments) {
                $expectedValues.Add((ConvertFrom-Json -InputObject $document -AsHashtable -NoEnumerate))
            }
            $expectedCanonical = ConvertTo-YamlSuiteCanonicalValue `
                -Value ([object[]] $expectedValues.ToArray()) -SortMappings
            $jsonExpected = $expectedCanonical
            $jsonActual = $projectedJsonCanonical
            if ($projectedJsonCanonical -ceq $expectedCanonical) {
                $jsonResult = 'Pass'
            } else {
                $reason = Get-YamlSuiteJsonPolicyReason `
                    -ExpectedValues ([object[]] $expectedValues.ToArray()) `
                    -ActualValues ([object[]] $projectedValues)
                if ($reason) {
                    $jsonResult = 'PolicyDifference'
                    $jsonReason = $reason
                } else {
                    $jsonResult = 'Fail'
                    $jsonReason = 'ConstructedValueMismatch'
                }
            }
        }
    }

    if ($CompareOutYaml -and $hasOutYaml) {
        if ($syntaxResult -eq 'PolicyDifference') {
            $outYamlResult = 'PolicyDifference'
            $outYamlReason = $syntaxReason
        } elseif ($null -eq $stream -or $expectsError -or
            $null -eq $projectedValues) {
            $outYamlResult = 'NotApplicable'
            if ($projectionError) { $outYamlReason = $projectionError }
        } else {
            $outYaml = [System.IO.File]::ReadAllText($outYamlPath, [System.Text.UTF8Encoding]::new($false, $true))
            try {
                $outStream = Invoke-InYamlModule -ScriptBlock $readYamlSuiteStream -Arguments @($outYaml)
                $outValues = (Invoke-InYamlModule -ScriptBlock $projectYamlSuiteStream -Arguments (, $outStream.Value)).Value
                $outCanonical = ConvertTo-YamlSuiteCanonicalValue -Value ([object[]] $outValues)
                $outReference = ConvertTo-YamlSuiteReferenceSignature -Value ([object[]] $outValues)
                $outYamlCanonical = $outCanonical
                $outYamlReference = $outReference
                if ($outCanonical -cne $projectedCanonical) {
                    $outYamlResult = 'Fail'
                    $outYamlReason = 'OutYamlConstructionMismatch'
                } elseif ($outReference -cne $projectedReference) {
                    $outYamlResult = 'Fail'
                    $outYamlReason = 'OutYamlReferenceMismatch'
                } else {
                    $outYamlResult = 'Pass'
                }
            } catch {
                if ($_.Exception.Data.Contains('IsYamlException')) {
                    $outYamlResult = 'Fail'
                    $outYamlReason = [string] $_.Exception.Data['YamlErrorId']
                } else {
                    throw
                }
            }
        }
    }

    if ($CompareEmitYaml -and $hasEmitYaml) {
        try {
            $emitYaml = [System.IO.File]::ReadAllText(
                $emitYamlPath,
                [System.Text.UTF8Encoding]::new($false, $true)
            )
            $isValidFixture = Invoke-InYamlModule -ScriptBlock $testYamlSuiteText `
                -Arguments @($emitYaml)
            if (-not $isValidFixture) {
                $emitYamlResult = 'Fail'
                $emitYamlReason = 'EmitYamlInvalid'
            } else {
                $fixtureValues = (Invoke-InYamlModule -ScriptBlock $projectYamlSuiteText `
                        -Arguments @($emitYaml)).Value
                $fixtureCanonical = ConvertTo-YamlSuiteCanonicalValue `
                    -Value ([object[]] $fixtureValues)
                $fixtureReference = ConvertTo-YamlSuiteReferenceSignature `
                    -Value ([object[]] $fixtureValues)

                if ($null -ne $projectedCanonical -and
                    ($fixtureCanonical -cne $projectedCanonical -or
                    $fixtureReference -cne $projectedReference)) {
                    $emitYamlResult = 'Fail'
                    $emitYamlReason = 'EmitYamlRepresentationMismatch'
                    $emitYamlExpected = $projectedCanonical
                    $emitYamlActual = $fixtureCanonical
                    $emitYamlExpectedReference = $projectedReference
                    $emitYamlActualReference = $fixtureReference
                } else {
                    $fixtureEmittedDocuments = [System.Collections.Generic.List[string]]::new()
                    foreach ($fixtureValue in $fixtureValues) {
                        $fixtureEmitted = Invoke-InYamlModule -ScriptBlock {
                            param ($InputValue)
                            ConvertTo-Yaml -InputObject $InputValue -ExplicitDocumentStart
                        } -Arguments (, $fixtureValue)
                        $fixtureEmittedDocuments.Add([string] $fixtureEmitted)
                    }
                    $fixtureEmittedText = $fixtureEmittedDocuments.ToArray() -join "`n"
                    $isValidFixtureEmit = Invoke-InYamlModule `
                        -ScriptBlock $testYamlSuiteText -Arguments @($fixtureEmittedText)
                    if (-not $isValidFixtureEmit) {
                        $emitYamlResult = 'Fail'
                        $emitYamlReason = 'EmittedYamlInvalid'
                    } else {
                        $fixtureRoundTripValues = (
                            Invoke-InYamlModule -ScriptBlock $projectYamlSuiteText `
                                -Arguments @($fixtureEmittedText)
                        ).Value
                        $fixtureRoundCanonical = ConvertTo-YamlSuiteCanonicalValue `
                            -Value ([object[]] $fixtureRoundTripValues)
                        $fixtureRoundReference = ConvertTo-YamlSuiteReferenceSignature `
                            -Value ([object[]] $fixtureRoundTripValues)
                        $emitYamlExpected = $fixtureCanonical
                        $emitYamlActual = $fixtureRoundCanonical
                        $emitYamlExpectedReference = $fixtureReference
                        $emitYamlActualReference = $fixtureRoundReference
                    }
                    if ($emitYamlResult -ne 'Fail' -and
                        $fixtureRoundCanonical -ceq $fixtureCanonical -and
                        $fixtureRoundReference -ceq $fixtureReference) {
                        $emitYamlResult = 'Pass'
                    } elseif ($emitYamlResult -ne 'Fail') {
                        $emitYamlResult = 'Fail'
                        $emitYamlReason = 'EmitYamlRoundTripMismatch'
                    }
                }
            }
        } catch [System.NotSupportedException] {
            $emitYamlResult = 'Fail'
            $emitYamlReason = 'UnsupportedEmissionType'
        } catch {
            if ($_.Exception.Data.Contains('IsYamlException')) {
                $emitYamlResult = 'Fail'
                $emitYamlReason = [string] $_.Exception.Data['YamlErrorId']
            } else {
                throw
            }
        }
    }

    if ($CompareSelfRoundTrip) {
        if ($syntaxResult -eq 'PolicyDifference') {
            $selfRoundTripResult = 'PolicyDifference'
            $selfRoundTripReason = $syntaxReason
        } elseif ($null -eq $stream -or $expectsError) {
            $selfRoundTripResult = 'NotApplicable'
            if ($expectsError) { $selfRoundTripReason = 'InvalidSyntax' }
        } elseif ($projectionError) {
            $selfRoundTripResult = 'Fail'
            $selfRoundTripReason = $projectionError
        } else {
            try {
                $emittedDocuments = [System.Collections.Generic.List[string]]::new()
                foreach ($value in $projectedValues) {
                    $emitted = Invoke-InYamlModule -ScriptBlock {
                        param ($InputValue)
                        ConvertTo-Yaml -InputObject $InputValue -ExplicitDocumentStart
                    } -Arguments (, $value)
                    $emittedDocuments.Add([string] $emitted)
                }
                $emittedText = ($emittedDocuments.ToArray() -join "`n")
                $isValidEmit = Invoke-InYamlModule -ScriptBlock $testYamlSuiteText `
                    -Arguments @($emittedText)
                if (-not $isValidEmit) {
                    $selfRoundTripResult = 'Fail'
                    $selfRoundTripReason = 'EmittedYamlInvalid'
                } else {
                    $roundTripValues = (Invoke-InYamlModule -ScriptBlock $projectYamlSuiteText `
                            -Arguments @($emittedText)).Value
                    $roundCanonical = ConvertTo-YamlSuiteCanonicalValue -Value ([object[]] $roundTripValues)
                    $roundReference = ConvertTo-YamlSuiteReferenceSignature -Value ([object[]] $roundTripValues)
                    $selfRoundTripCanonical = $roundCanonical
                    $selfRoundTripReference = $roundReference
                    if ($roundCanonical -ceq $projectedCanonical -and $roundReference -ceq $projectedReference) {
                        $selfRoundTripResult = 'Pass'
                    } else {
                        $selfRoundTripResult = 'Fail'
                        $selfRoundTripReason = 'SelfRoundTripMismatch'
                    }
                }
            } catch [System.NotSupportedException] {
                $selfRoundTripResult = 'Fail'
                $selfRoundTripReason = 'UnsupportedEmissionType'
            } catch {
                if ($_.Exception.Data.Contains('IsYamlException')) {
                    $selfRoundTripResult = 'Fail'
                    $selfRoundTripReason = [string] $_.Exception.Data['YamlErrorId']
                } else {
                    throw
                }
            }
        }
    }

    [pscustomobject]@{
        Case                 = $casePath
        ExpectsError         = $expectsError
        HasJson              = $hasJson
        HasEvent             = $hasEvent
        HasOutYaml           = $hasOutYaml
        HasEmitYaml          = $hasEmitYaml
        SyntaxResult         = $syntaxResult
        SyntaxReason         = $syntaxReason
        EventResult          = $eventResult
        EventReason          = $eventReason
        JsonResult           = $jsonResult
        JsonReason           = $jsonReason
        OutYamlResult        = $outYamlResult
        OutYamlReason        = $outYamlReason
        EmitYamlResult       = $emitYamlResult
        EmitYamlReason       = $emitYamlReason
        SelfRoundTripResult  = $selfRoundTripResult
        SelfRoundTripReason  = $selfRoundTripReason
        EventExpected        = $eventExpected
        EventActual          = $eventActual
        JsonExpected         = $jsonExpected
        JsonActual           = $jsonActual
        OutYamlActual        = $outYamlCanonical
        OutYamlRefs          = $outYamlReference
        EmitYamlExpected     = $emitYamlExpected
        EmitYamlActual       = $emitYamlActual
        EmitYamlExpectedRefs = $emitYamlExpectedReference
        EmitYamlActualRefs   = $emitYamlActualReference
        SelfRoundTripActual  = $selfRoundTripCanonical
        SelfRoundTripRefs    = $selfRoundTripReference
        ProjectedActual      = $projectedCanonical
        ProjectedRefs        = $projectedReference
    }
}
