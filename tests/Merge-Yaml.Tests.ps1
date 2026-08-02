#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0'; MaximumVersion = '6.*' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'Required for Pester tests'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Required for Pester tests'
)]
[CmdletBinding()]
param()

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestBootstrap.ps1')

    function Get-MergeYamlFailure {
        <#
            .SYNOPSIS
            Captures one expected terminating Merge-Yaml error.
        #>
        param (
            [Parameter(Mandatory)]
            [scriptblock] $Action
        )

        try {
            $null = & $Action
        } catch {
            return $_
        }
        throw 'The YAML merge unexpectedly succeeded.'
    }

    function Get-MergeYamlGraphFact {
        <#
            .SYNOPSIS
            Returns representation graph facts without projecting YAML values.
        #>
        param (
            [Parameter(Mandatory)]
            [string] $Yaml
        )

        $implementation = {
            param ([string] $YamlText)

            $documents = (Read-YamlStreamCore -Yaml $YamlText -Depth 100 -MaxNodes 10000 `
                    -MaxAliases 1000 -MaxScalarLength 1048576 -MaxTagLength 1024 `
                    -MaxTotalTagLength 65536 -MaxNumericLength 4096).Value
            $visited = [System.Collections.Generic.HashSet[int]]::new()
            $stack = [System.Collections.Generic.Stack[object]]::new()
            foreach ($document in $documents) {
                $stack.Push($document)
            }
            $aliases = 0
            $nodes = 0
            $tags = [System.Collections.Generic.List[string]]::new()
            while ($stack.Count -gt 0) {
                $node = $stack.Pop()
                if (-not $visited.Add($node.Id)) {
                    continue
                }
                $nodes++
                if (-not [string]::IsNullOrEmpty($node.Tag)) {
                    $tags.Add([string] $node.Tag)
                }
                if ($node.Kind -eq 'Alias') {
                    $aliases++
                    $stack.Push($node.Target)
                } elseif ($node.Kind -eq 'Sequence') {
                    foreach ($item in $node.Items) {
                        $stack.Push($item)
                    }
                } elseif ($node.Kind -eq 'Mapping') {
                    foreach ($entry in $node.Entries) {
                        $stack.Push($entry.Value)
                        $stack.Push($entry.Key)
                    }
                }
            }

            [pscustomobject]@{
                DocumentCount = $documents.Count
                NodeCount     = $nodes
                AliasCount    = $aliases
                Tags          = [string[]] $tags.ToArray()
            }
        }

        $loadedModule = Get-Module -Name Yaml | Select-Object -First 1
        if ($null -eq $loadedModule) {
            return & $implementation $Yaml
        }
        return & $loadedModule $implementation $Yaml
    }

    function Measure-MergeYamlWork {
        <#
            .SYNOPSIS
            Captures the deterministic merge operation count from the debug stream.
        #>
        param (
            [Parameter(Mandatory)]
            [string[]] $InputObject,

            [Parameter()]
            [hashtable] $Parameters = @{}
        )

        $records = @(Merge-Yaml -InputObject $InputObject @Parameters -Debug 5>&1)
        $debugText = $records |
            ForEach-Object ToString |
            Where-Object { $_ -like '*Merge-Yaml work operations:*' } |
            Select-Object -Last 1
        if ($null -eq $debugText -or
            $debugText -notmatch 'Merge-Yaml work operations: (?<WorkCount>\d+)') {
            throw 'Merge-Yaml did not report its deterministic work count.'
        }
        $output = $records |
            Where-Object { $_ -isnot [System.Management.Automation.DebugRecord] } |
            Select-Object -First 1

        [pscustomobject]@{
            Output = [string] $output
            Count  = [long] $Matches.WorkCount
        }
    }
}

Describe 'Merge-Yaml' {
    Context 'Public contract' {
        It 'exposes the documented advanced string merge contract' {
            $command = Get-Command -Name Merge-Yaml
            $inputParameter = $command.Parameters['InputObject']
            $inputAttribute = $inputParameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $allowEmptyString = $inputParameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.AllowEmptyStringAttribute] }
            $indentRange = $command.Parameters['Indent'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $sequenceSet = $command.Parameters['SequenceAction'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $conflictSet = $command.Parameters['ConflictAction'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $nullSet = $command.Parameters['NullAction'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            $help = Get-Help -Name Merge-Yaml -Full

            $command.CmdletBinding | Should -BeTrue
            $inputParameter.ParameterType | Should -Be ([string[]])
            $inputAttribute.Mandatory | Should -BeTrue
            $inputAttribute.Position | Should -Be 0
            $inputAttribute.ValueFromPipeline | Should -BeTrue
            $allowEmptyString | Should -Not -BeNullOrEmpty
            @($command.OutputType.Type) | Should -Contain ([string])
            @($sequenceSet.ValidValues) | Should -Be @('Replace', 'Append', 'Unique')
            @($conflictSet.ValidValues) | Should -Be @('Replace', 'Error')
            @($nullSet.ValidValues) | Should -Be @('Replace', 'Ignore')
            $indentRange.MinRange | Should -Be 2
            $indentRange.MaxRange | Should -Be 9
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description.Text | Should -Match 'complete YAML stream'
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
        }
    }

    It 'mirrors every parser safety range' -ForEach @(
        @{ Name = 'Depth'; Minimum = 1; Maximum = 128 }
        @{ Name = 'MaxNodes'; Minimum = 1; Maximum = 2147483647 }
        @{ Name = 'MaxAliases'; Minimum = 0; Maximum = 2147483647 }
        @{ Name = 'MaxScalarLength'; Minimum = 1; Maximum = 2147483647 }
        @{ Name = 'MaxTagLength'; Minimum = 1; Maximum = 1048576 }
        @{ Name = 'MaxTotalTagLength'; Minimum = 1; Maximum = 2147483647 }
        @{ Name = 'MaxNumericLength'; Minimum = 1; Maximum = 1048576 }
    ) {
        $range = (Get-Command Merge-Yaml).Parameters[$Name].Attributes |
            Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }

        $range.MinRange | Should -Be $Minimum
        $range.MaxRange | Should -Be $Maximum
    }

    It 'accepts direct arrays and complete pipeline stream records' {
        $base = "root:`n  first: 1"
        $overlay = "root:`n  second: 2"
        $expected = "root:`n  first: 1`n  second: 2" | Format-Yaml

        (Merge-Yaml -InputObject @($base, $overlay)) | Should -BeExactly $expected
        (@($base, $overlay) | Merge-Yaml) | Should -BeExactly $expected
    }

    It 'emits exactly one LF-only string without a final newline' {
        $result = @(Merge-Yaml -InputObject @("one: 1`r`n", "two: 2`r`n"))

        $result.Count | Should -Be 1
        $result[0] | Should -BeOfType [string]
        $result[0] | Should -Not -Match "`r"
        $result[0].EndsWith("`n", [System.StringComparison]::Ordinal) |
            Should -BeFalse
    }

    It 'requires at least two complete streams' {
        $failure = Get-MergeYamlFailure { Merge-Yaml -InputObject 'one: 1' }

        $failure.Exception.Data['YamlErrorId'] | Should -BeExactly 'YamlMergeInputCount'
        $failure.FullyQualifiedErrorId | Should -Be 'YamlMergeInputCount,Merge-Yaml'
    }
}

Context 'Mapping precedence and order' {
    It 'merges mappings recursively while retaining and appending key positions' {
        $base = @'
root:
  keep: 1
  replace: old
tail: base
'@
        $overlay = @'
root:
  replace: new
  added: true
'@
        $expected = @'
root:
  keep: 1
  replace: new
  added: true
tail: base
'@ | Format-Yaml

        (Merge-Yaml -InputObject @($base, $overlay)) | Should -BeExactly $expected
    }

    It 'applies later precedence across three or more streams' {
        $first = "value: first`nfirst: true"
        $second = "value: second`nsecond: true"
        $third = "value: third`nthird: true"
        $expected = "value: third`nfirst: true`nsecond: true`nthird: true" | Format-Yaml

        (Merge-Yaml $first, $second, $third) | Should -BeExactly $expected
    }

    It 'merges structurally equal complex mapping keys' {
        $base = @'
? [region, { port: 443 }]
: { first: 1 }
'@
        $overlay = @'
?
  - region
  - port: 443
: { second: 2 }
'@
        $merged = Merge-Yaml $base, $overlay
        $result = $merged | ConvertFrom-Yaml -AsHashtable
        $entry = @($result.GetEnumerator())[0]

        $result.Count | Should -Be 1
        $entry.Value['first'] | Should -Be 1
        $entry.Value['second'] | Should -Be 2
    }

    It 'does not merge unequal complex keys that share a candidate bucket' {
        $base = @'
? [region, { port: 443 }]
: first
'@
        $overlay = @'
? [zone, { port: 443 }]
: second
'@
        $result = Merge-Yaml $base, $overlay | ConvertFrom-Yaml -AsHashtable

        $result.Count | Should -Be 2
        @($result.Values) | Should -Be @('first', 'second')
    }

    It 're-buckets a shared structural key after its target is recursively mutated' `
        -ForEach @(
        @{ Action = 'Replace' }
        @{ Action = 'Error' }
    ) {
        $base = "target: &key {x: 1}`n? *key`n: base"
        $overlay = "target: {y: 2}`n? {x: 1, y: 2}`n: overlay"

        if ($Action -eq 'Error') {
            $failure = Get-MergeYamlFailure {
                Merge-Yaml $base, $overlay -ConflictAction Error
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlMergeConflict'
            $failure.Exception.Message | Should -Match 'input index 1'
            return
        }

        $result = Merge-Yaml $base, $overlay | ConvertFrom-Yaml -AsHashtable

        $result.Count | Should -Be 2
        $result['target'].Count | Should -Be 2
        @($result.Values) | Should -Contain 'overlay'
    }

    It 're-buckets tagged shared keys across later overlay streams' {
        $base = @'
target: &key !item { x: 1 }
? *key
: base
'@
        $firstOverlay = 'target: !item { y: 2 }'
        $secondOverlay = @'
? !item { x: 1, y: 2 }
: final
'@

        $merged = Merge-Yaml $base, $firstOverlay, $secondOverlay
        $result = $merged | ConvertFrom-Yaml -AsHashtable
        $facts = Get-MergeYamlGraphFact -Yaml $merged

        $result.Count | Should -Be 2
        @($result.Values) | Should -Contain 'final'
        @($facts.Tags) | Should -Contain '!item'
    }

    It 'keeps YAML 1.1 merge syntax as ordinary mapping data' {
        $base = @'
<<:
  fromBase: true
ordinary: value
'@
        $overlay = @'
<<:
  fromOverlay: true
'@
        $result = Merge-Yaml $base, $overlay | ConvertFrom-Yaml -AsHashtable

        @($result.Keys) | Should -Be @('<<', 'ordinary')
        $result['<<']['fromBase'] | Should -BeTrue
        $result['<<']['fromOverlay'] | Should -BeTrue
        $result.Contains('fromBase') | Should -BeFalse
        $result.Contains('fromOverlay') | Should -BeFalse
    }
}

Context 'Sequence policies' {
    It 'applies the requested compatible-sequence action' -ForEach @(
        @{
            Action   = 'Replace'
            Expected = "items:`n- two`n- three"
        }
        @{
            Action   = 'Append'
            Expected = "items:`n- one`n- two`n- two`n- three"
        }
        @{
            Action   = 'Unique'
            Expected = "items:`n- one`n- two`n- three"
        }
    ) {
        $base = 'items: [one, two]'
        $overlay = 'items: [two, three]'

        $actual = Merge-Yaml $base, $overlay -SequenceAction $Action

        $actual | Should -BeExactly ($Expected | Format-Yaml)
    }

    It 'retains equal sequences under every action' -ForEach @(
        @{ Action = 'Replace' }
        @{ Action = 'Append' }
        @{ Action = 'Unique' }
    ) {
        $base = "items: &items [one, two]`ncopy: *items"
        $merged = Merge-Yaml $base, $base -SequenceAction $Action -ConflictAction Error
        $result = $merged | ConvertFrom-Yaml -AsHashtable

        $merged | Should -BeExactly ($base | Format-Yaml)
        [object]::ReferenceEquals($result['items'], $result['copy']) |
            Should -BeTrue
    }

    It 'deduplicates scalar, complex, tagged, and cyclic values structurally' {
        $base = @'
items:
  - one
  - { key: value }
  - !item tagged
  - &cycle { self: *cycle }
'@
        $overlay = @'
items:
  - one
  - key: value
  - !item tagged
  - !other tagged
  - &other { self: *other }
  - added
'@
        $merged = Merge-Yaml $base, $overlay -SequenceAction Unique
        $result = $merged | ConvertFrom-Yaml -AsHashtable
        $facts = Get-MergeYamlGraphFact -Yaml $merged

        $result['items'].Count | Should -Be 6
        $result['items'][5] | Should -Be 'added'
        [object]::ReferenceEquals(
            $result['items'][3],
            $result['items'][3]['self']
        ) | Should -BeTrue
        @($facts.Tags) | Should -Contain '!item'
        @($facts.Tags) | Should -Contain '!other'
    }

    It 'preserves overlay sharing and cycles while appending' {
        $base = 'items: [base]'
        $overlay = @'
items:
  - &shared { value: overlay }
  - *shared
  - &cycle { self: *cycle }
'@
        $merged = Merge-Yaml $base, $overlay -SequenceAction Append
        $result = $merged | ConvertFrom-Yaml -AsHashtable

        [object]::ReferenceEquals($result['items'][1], $result['items'][2]) |
            Should -BeTrue
        [object]::ReferenceEquals(
            $result['items'][3],
            $result['items'][3]['self']
        ) | Should -BeTrue
    }

    It 'invalidates a retained cyclic-item index after shared tagged-node mutation' {
        $base = @'
target: &cycle !cycle
  self: *cycle
  x: 1
items: [*cycle]
'@
        $firstOverlay = 'items: [added]'
        $secondOverlay = @'
target: !cycle { y: 2 }
items:
  - &other !cycle
    self: *other
    x: 1
    y: 2
'@

        $merged = Merge-Yaml $base, $firstOverlay, $secondOverlay `
            -SequenceAction Unique
        $result = $merged | ConvertFrom-Yaml -AsHashtable

        $result['items'].Count | Should -Be 2
        [object]::ReferenceEquals($result['target'], $result['items'][0]) |
            Should -BeTrue
        $result['target']['y'] | Should -Be 2
    }

    It 'deduplicates structurally equal cycles with different graph lengths' {
        $base = 'items: [&self [*self]]'
        $overlay = 'items: [&outer [&inner [*outer]], added]'

        $merged = Merge-Yaml $base, $overlay -SequenceAction Unique
        $result = $merged | ConvertFrom-Yaml -AsHashtable

        $result['items'].Count | Should -Be 2
        [object]::ReferenceEquals(
            $result['items'][0],
            $result['items'][0][0]
        ) | Should -BeTrue
        $result['items'][1] | Should -Be 'added'
    }
}

Context 'Conflict and null policies' {
    It 'replaces incompatible scalar values by default' {
        (Merge-Yaml 'value: old', 'value: new') |
            Should -BeExactly ('value: new' | Format-Yaml)
    }

    It 'rejects unequal scalar, kind, and effective-tag conflicts with context' -ForEach @(
        @{ Base = 'value: old'; Overlay = 'value: new'; Path = '\$\.value' }
        @{ Base = 'value: { key: one }'; Overlay = 'value: [one]'; Path = '\$\.value' }
        @{ Base = '!first { key: one }'; Overlay = '!second { key: one }'; Path = '\$' }
    ) {
        $failure = Get-MergeYamlFailure {
            Merge-Yaml $Base, $Overlay -ConflictAction Error
        }

        $failure.Exception.Data['YamlErrorId'] | Should -BeExactly 'YamlMergeConflict'
        $failure.Exception.Message | Should -Match 'input index 1'
        $failure.Exception.Message | Should -Match 'document index 0'
        $failure.Exception.Message | Should -Match $Path
    }

    It 'retains structurally equal nodes under Error conflict policy' {
        $base = '!same { nested: [one, { two: 2 }] }'
        $overlay = '!same { nested: [one, { two: 2 }] }'

        (Merge-Yaml $base, $overlay -ConflictAction Error) |
            Should -BeExactly ($base | Format-Yaml)
    }

    It 'does not apply sequence actions across incompatible effective tags' {
        $failure = Get-MergeYamlFailure {
            Merge-Yaml '!first [one]', '!second [two]' `
                -SequenceAction Append -ConflictAction Error
        }

        $failure.Exception.Data['YamlErrorId'] | Should -BeExactly 'YamlMergeConflict'
        $failure.Exception.Message | Should -Match 'sequence tag'
    }

    It 'applies nested null replacement and ignoring' {
        $base = "root:`n  value: retained"
        $overlay = "root:`n  value: null"

        $replace = Merge-Yaml $base, $overlay | ConvertFrom-Yaml -AsHashtable
        $ignore = Merge-Yaml $base, $overlay -NullAction Ignore |
            ConvertFrom-Yaml -AsHashtable

        $replace['root']['value'] | Should -BeNullOrEmpty
        $ignore['root']['value'] | Should -Be 'retained'
    }

    It 'applies root null replacement and ignoring' {
        $base = 'value: retained'

        (Merge-Yaml $base, 'null' | ConvertFrom-Yaml) | Should -BeNullOrEmpty
        (Merge-Yaml $base, 'null' -NullAction Ignore) |
            Should -BeExactly ($base | Format-Yaml)
    }
}

Context 'Tags and graph identity' {
    It 'recursively merges compatible standard and unknown mapping tags' -ForEach @(
        @{
            Base        = '!!map { first: 1 }'
            Overlay     = '{ second: 2 }'
            ExpectedTag = 'tag:yaml.org,2002:map'
        }
        @{
            Base        = '!<tag:example.test,2026:item> { first: 1 }'
            Overlay     = '!<tag:example.test,2026:item> { second: 2 }'
            ExpectedTag = 'tag:example.test,2026:item'
        }
    ) {
        $merged = Merge-Yaml $Base, $Overlay
        $root = Get-TestYamlRepresentationRoot -Yaml $merged
        $projected = $merged | ConvertFrom-Yaml -AsHashtable

        $root.Tag | Should -BeExactly $ExpectedTag
        $projected['first'] | Should -Be 1
        $projected['second'] | Should -Be 2
    }

    It 'preserves base aliases when their target is recursively merged' {
        $base = @'
root: &shared
  base: true
copy: *shared
'@
        $overlay = @'
root:
  overlay: true
'@
        $result = Merge-Yaml $base, $overlay | ConvertFrom-Yaml -AsHashtable

        $result['root']['base'] | Should -BeTrue
        $result['copy']['overlay'] | Should -BeTrue
        [object]::ReferenceEquals($result['root'], $result['copy']) |
            Should -BeTrue
    }

    It 'preserves shared overlay mappings across matched base entries' {
        $base = @'
first: { base: one }
second: { base: two }
'@
        $overlay = @'
first: &shared { overlay: true }
second: *shared
'@
        $result = Merge-Yaml $base, $overlay | ConvertFrom-Yaml -AsHashtable

        $result['first']['overlay'] | Should -BeTrue
        [object]::ReferenceEquals($result['first'], $result['second']) |
            Should -BeTrue
    }

    It 'preserves a recursively merged overlay cycle' {
        $base = 'node: { base: true }'
        $overlay = @'
node: &cycle
  overlay: true
  self: *cycle
'@
        $merged = Merge-Yaml $base, $overlay
        $result = $merged | ConvertFrom-Yaml -AsHashtable

        $result['node']['base'] | Should -BeTrue
        $result['node']['overlay'] | Should -BeTrue
        [object]::ReferenceEquals($result['node'], $result['node']['self']) |
            Should -BeTrue
        $merged | Test-Yaml | Should -BeTrue
    }
}

Context 'Documents, validation, and limits' {
    It 'merges equal positive multi-document streams by document index' {
        $base = "---`nfirst: base`n---`nsecond: base"
        $overlay = "---`nfirstOverlay: true`n---`nsecond: overlay"
        $merged = Merge-Yaml $base, $overlay
        $documents = @($merged | ConvertFrom-Yaml -AsHashtable)

        $documents.Count | Should -Be 2
        $documents[0]['first'] | Should -Be 'base'
        $documents[0]['firstOverlay'] | Should -BeTrue
        $documents[1]['second'] | Should -Be 'overlay'
    }

    It 'keeps explicit empty documents as positive document records' {
        $base = "---`nvalue: base`n---"
        $overlay = "---`nvalue: overlay`n---"
        $merged = Merge-Yaml $base, $overlay
        $documents = @($merged | ConvertFrom-Yaml -AsHashtable)

        $documents.Count | Should -Be 2
        $documents[0]['value'] | Should -Be 'overlay'
        $documents[1] | Should -BeNullOrEmpty
    }

    It 'rejects no-document streams with their zero-based input index' -ForEach @(
        @{ Empty = '' }
        @{ Empty = "# comment only`n" }
    ) {
        $failure = Get-MergeYamlFailure {
            Merge-Yaml 'value: base', $Empty
        }

        $failure.Exception.Data['YamlErrorId'] | Should -BeExactly 'YamlMergeEmptyStream'
        $failure.Exception.Message | Should -Match 'input index 1'
        $failure.Exception.Message | Should -Match '0 documents'
    }

    It 'rejects document-count mismatches with expected and actual counts' {
        $failure = Get-MergeYamlFailure {
            Merge-Yaml 'one: 1', "---`ntwo: 2`n---`nthree: 3"
        }

        $failure.Exception.Data['YamlErrorId'] |
            Should -BeExactly 'YamlMergeDocumentCountMismatch'
        $failure.Exception.Message | Should -Match 'input index 1'
        $failure.Exception.Message | Should -Match '2 documents'
        $failure.Exception.Message | Should -Match 'expected 1'
    }

    It 'preserves parser invalid-input classifications' {
        $failure = Get-MergeYamlFailure {
            Merge-Yaml 'valid: true', '[invalid'
        }

        $failure.Exception.Data['YamlErrorId'] |
            Should -BeExactly 'YamlInvalidFlowCollection'
        $failure.FullyQualifiedErrorId |
            Should -Be 'YamlInvalidFlowCollection,Merge-Yaml'
    }

    It 'preserves every parser resource classification' -ForEach @(
        @{ Yaml = "a:`n  b:`n    c: value"; Parameters = @{ Depth = 2 } }
        @{ Yaml = '[one, two]'; Parameters = @{ MaxNodes = 2 } }
        @{ Yaml = "a: &a value`nb: *a"; Parameters = @{ MaxAliases = 0 } }
        @{ Yaml = 'value: long'; Parameters = @{ MaxScalarLength = 4 } }
        @{ Yaml = '!long value'; Parameters = @{ MaxTagLength = 2 } }
        @{
            Yaml       = "!a one`n---`n!b two"
            Parameters = @{ MaxTotalTagLength = 3 }
        }
        @{ Yaml = '123'; Parameters = @{ MaxNumericLength = 2 } }
    ) {
        $parseFailure = Get-MergeYamlFailure {
            $Yaml | Format-Yaml @Parameters
        }
        $mergeFailure = Get-MergeYamlFailure {
            Merge-Yaml 'valid: true', $Yaml @Parameters
        }

        $mergeFailure.Exception.Data['YamlErrorId'] |
            Should -BeExactly $parseFailure.Exception.Data['YamlErrorId']
        $mergeFailure.FullyQualifiedErrorId |
            Should -Be "$($parseFailure.Exception.Data['YamlErrorId']),Merge-Yaml"
    }

    It 'enforces the invocation-wide clone node budget' {
        $failure = Get-MergeYamlFailure {
            Merge-Yaml 'a: 1', '[overlay]' -MaxNodes 3
        }

        $failure.Exception.Data['YamlErrorId'] |
            Should -BeExactly 'YamlMergeNodeLimitExceeded'
    }

    It 'charges equality and candidate scans to one invocation work budget' {
        $base = '[{ a: 1 }, { b: 2 }]'
        $overlay = '[{ b: 2 }, { a: 1 }]'
        $failure = Get-MergeYamlFailure {
            Merge-Yaml $base, $overlay -SequenceAction Unique -MaxNodes 7
        }

        $failure.Exception.Data['YamlErrorId'] |
            Should -BeExactly 'YamlMergeWorkLimitExceeded'
        $failure.Exception.Data['YamlMergeWorkCount'] | Should -Be 8
        $failure.Exception.Data['YamlMergeWorkLimit'] | Should -Be 7
    }

    It 'keeps disjoint one-key overlay work linear' -ForEach @(
        @{ Size = 200 }
        @{ Size = 400 }
        @{ Size = 800 }
    ) {
        $streams = [System.Collections.Generic.List[string]]::new()
        $streams.Add('base: true')
        foreach ($index in 1..$Size) {
            $streams.Add("key${index}: ${index}")
        }
        $limit = 12 * $Size + 50

        $measurement = Measure-MergeYamlWork -InputObject $streams.ToArray() `
            -Parameters @{ MaxNodes = $limit }

        $measurement.Count | Should -BeLessOrEqual (10 * $Size + 20)
        $measurement.Output | Should -Not -BeNullOrEmpty
    }

    It 'keeps unique sequence append work linear' -ForEach @(
        @{ Size = 200 }
        @{ Size = 400 }
        @{ Size = 800 }
    ) {
        $streams = [System.Collections.Generic.List[string]]::new()
        $streams.Add('items: []')
        foreach ($index in 1..$Size) {
            $streams.Add("items: [value${index}]")
        }
        $limit = 31 * $Size + 100

        $measurement = Measure-MergeYamlWork -InputObject $streams.ToArray() `
            -Parameters @{ MaxNodes = $limit; SequenceAction = 'Unique' }

        $measurement.Count | Should -BeLessOrEqual (30 * $Size + 20)
        $measurement.Output | Should -Not -BeNullOrEmpty
    }

    It 'reuses fingerprints for shared complex keys throughout equality' -ForEach @(
        @{ Size = 20 }
        @{ Size = 40 }
        @{ Size = 80 }
    ) {
        $values = (1..$Size | ForEach-Object { "value$_" }) -join ', '
        $yaml = [System.Collections.Generic.List[string]]::new()
        $yaml.Add("shared: &key [$values]")
        $yaml.Add('maps:')
        foreach ($index in 1..$Size) {
            $yaml.Add('  - ? *key')
            $yaml.Add("    : value${index}")
        }
        $text = $yaml -join "`n"

        $measurement = Measure-MergeYamlWork -InputObject @($text, $text) `
            -Parameters @{ MaxNodes = 100000; ConflictAction = 'Error' }

        $measurement.Count | Should -BeLessOrEqual (20 * $Size + 50)
        $measurement.Output | Should -Not -BeNullOrEmpty
    }

    It 'deduplicates cyclic alias candidates before fingerprint traversal' -ForEach @(
        @{ Size = 20 }
        @{ Size = 40 }
        @{ Size = 80 }
    ) {
        $base = [System.Collections.Generic.List[string]]::new()
        $base.Add('items:')
        $base.Add('  - &shared')
        $base.Add('    self: *shared')
        foreach ($index in 1..$Size) {
            $base.Add("    field${index}: ${index}")
        }
        foreach ($index in 2..$Size) {
            $base.Add('  - *shared')
        }
        $overlay = [System.Collections.Generic.List[string]]::new()
        foreach ($line in $base) {
            $overlay.Add($line)
        }
        $overlay.Add('  - added')

        $measurement = Measure-MergeYamlWork -InputObject @(
            $base -join "`n"
            $overlay -join "`n"
        ) -Parameters @{ MaxNodes = 100000; SequenceAction = 'Unique' }

        $measurement.Count | Should -BeLessOrEqual (21 * $Size + 100)
        $measurement.Output | Should -Not -BeNullOrEmpty
    }

    It 'deduplicates hundreds of aliases before comparing one large mapping' {
        $aliasCount = 300
        $entryCount = 200
        $base = [System.Collections.Generic.List[string]]::new()
        $base.Add('shared: &shared')
        foreach ($index in 1..$entryCount) {
            $base.Add("  item${index}: ${index}")
        }
        foreach ($index in 1..$aliasCount) {
            $base.Add("alias${index}: *shared")
        }
        $overlay = [System.Collections.Generic.List[string]]::new()
        $overlay.Add('shared: &shared')
        $overlay.Add('  added: true')
        foreach ($index in 1..$aliasCount) {
            $overlay.Add("alias${index}: *shared")
        }

        $measurement = Measure-MergeYamlWork -InputObject @(
            $base -join "`n"
            $overlay -join "`n"
        ) -Parameters @{ MaxNodes = 12000 }
        $result = $measurement.Output | ConvertFrom-Yaml -AsHashtable

        $measurement.Count | Should -BeLessOrEqual 7000
        [object]::ReferenceEquals($result['shared'], $result['alias300']) |
            Should -BeTrue
    }

    It 'enforces resulting alias and tag budgets' -ForEach @(
        @{
            Base       = "a: &a one`nb: *a"
            Overlay    = "c: &c two`nd: *c"
            Parameters = @{ MaxAliases = 1 }
            ErrorId    = 'YamlMergeAliasLimitExceeded'
        }
        @{
            Base       = 'a: !x one'
            Overlay    = 'b: !y two'
            Parameters = @{ MaxTotalTagLength = 2 }
            ErrorId    = 'YamlMergeTagLimitExceeded'
        }
    ) {
        $failure = Get-MergeYamlFailure {
            Merge-Yaml $Base, $Overlay @Parameters
        }

        $failure.Exception.Data['YamlErrorId'] | Should -BeExactly $ErrorId
    }
}

Context 'Determinism and representation smoke coverage' {
    It 'is deterministic, leaves source text semantics unchanged, and self-parses' {
        $base = @'
root: &root
  first: 1
copy: *root
'@
        $overlay = @'
root:
  second: [two, three]
'@
        $baseBefore = $base | Format-Yaml
        $first = Merge-Yaml $base, $overlay -SequenceAction Unique -Indent 4
        $second = Merge-Yaml $base, $overlay -SequenceAction Unique -Indent 4

        $second | Should -BeExactly $first
        ($base | Format-Yaml) | Should -BeExactly $baseBefore
        $first | Test-Yaml | Should -BeTrue
        $first | Should -BeExactly ($first | Format-Yaml -Indent 4)
    }

    It 'retains representation features from selected corpus fixtures' -ForEach @(
        @{ Fixture = '2JQS.yaml' }
        @{ Fixture = '6BFJ.yaml' }
        @{ Fixture = '565N.yaml' }
        @{ Fixture = 'SBG9.yaml' }
    ) {
        $path = Join-Path $PSScriptRoot "fixtures\yaml-test-suite\$Fixture"
        $yaml = Get-Content -LiteralPath $path -Raw

        if ($Fixture -eq '2JQS.yaml') {
            { Merge-Yaml $yaml, $yaml } | Should -Throw
        } else {
            $merged = Merge-Yaml $yaml, $yaml -ConflictAction Error
            $facts = Get-MergeYamlGraphFact -Yaml $merged

            $merged | Test-Yaml | Should -BeTrue
            $facts.DocumentCount | Should -BeGreaterThan 0
            $merged | Should -BeExactly ($merged | Format-Yaml)
        }
    }
}
