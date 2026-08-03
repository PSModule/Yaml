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
    if ($null -eq ('YamlTests.InfiniteEnumerable' -as [type])) {
        Add-Type -TypeDefinition @'
namespace YamlTests
{
    using System;
    using System.Collections;

    public sealed class InfiniteEnumerable : IEnumerable
    {
        private readonly object value;
        public int MoveNextCount { get; private set; }
        public int DisposeCount { get; private set; }

        public InfiniteEnumerable() : this(1) { }
        public InfiniteEnumerable(object value) { this.value = value; }
        public IEnumerator GetEnumerator() { return new Enumerator(this, value); }

        private sealed class Enumerator : IEnumerator, IDisposable
        {
            private readonly InfiniteEnumerable owner;
            private readonly object value;

            public Enumerator(InfiniteEnumerable owner, object value)
            {
                this.owner = owner;
                this.value = value;
            }

            public object Current { get { return value; } }

            public bool MoveNext()
            {
                owner.MoveNextCount++;
                return true;
            }

            public void Reset() { throw new NotSupportedException(); }
            public void Dispose() { owner.DisposeCount++; }
        }
    }

    public sealed class OneShotEnumerable : IEnumerable
    {
        private readonly object[] values;
        public int GetEnumeratorCount { get; private set; }
        public int MoveNextCount { get; private set; }
        public int DisposeCount { get; private set; }

        public OneShotEnumerable(object[] values) { this.values = values; }

        public IEnumerator GetEnumerator()
        {
            GetEnumeratorCount++;
            if (GetEnumeratorCount > 1)
            {
                throw new InvalidOperationException("The enumerable was consumed more than once.");
            }
            return new Enumerator(this, values);
        }

        private sealed class Enumerator : IEnumerator, IDisposable
        {
            private readonly OneShotEnumerable owner;
            private readonly object[] values;
            private int index = -1;

            public Enumerator(OneShotEnumerable owner, object[] values)
            {
                this.owner = owner;
                this.values = values;
            }

            public object Current { get { return values[index]; } }
            public bool MoveNext()
            {
                owner.MoveNextCount++;
                index++;
                return index < values.Length;
            }
            public void Reset() { throw new NotSupportedException(); }
            public void Dispose() { owner.DisposeCount++; }
        }
    }
}
'@
    }

    function Get-YamlTestInfinitePipeline {
        <#
            .SYNOPSIS
            Produces an unbounded stream for resource-limit tests.
        #>
        param ([string] $Item = 'value')

        while ($true) {
            $script:YamlTestPipelineCount++
            $Item
        }
    }
}

Describe 'ConvertTo-Yaml' {
    Context 'Supported values' {
        It 'serializes mappings, sequences, and core scalars to valid YAML' {
            $inputObject = [ordered]@{
                name    = 'Ada'
                active  = $true
                count   = 42
                ratio   = 1.5
                nothing = $null
                items   = @('one', 'two')
            }

            $yaml = ConvertTo-Yaml -InputObject $inputObject
            $result = $yaml | ConvertFrom-Yaml -AsHashtable

            $yaml | Should -BeOfType [string]
            ($yaml | Test-Yaml) | Should -BeTrue
            $result['name'] | Should -Be 'Ada'
            $result['active'] | Should -BeTrue
            $result['count'] | Should -Be 42
            $result['ratio'] | Should -Be 1.5
            $result['nothing'] | Should -BeNullOrEmpty
            $result['items'] | Should -Be @('one', 'two')
        }

        It 'quotes strings that resemble core-schema values' {
            $inputObject = [ordered]@{
                boolean = 'true'
                integer = '42'
                null    = 'null'
                empty   = ''
            }

            $result = ($inputObject | ConvertTo-Yaml) | ConvertFrom-Yaml -AsHashtable

            $result['boolean'] | Should -BeOfType [string]
            $result['integer'] | Should -BeOfType [string]
            $result['null'] | Should -BeOfType [string]
            $result['empty'] | Should -BeOfType [string]
        }

        It 'escapes quoted scalar content without duplicating characters' {
            $inputObject = [ordered]@{
                quote     = 'a"b'
                slash     = 'a\b'
                multiline = "one`ntwo"
            }

            $yaml = $inputObject | ConvertTo-Yaml
            $result = $yaml | ConvertFrom-Yaml -AsHashtable

            ($yaml | Test-Yaml) | Should -BeTrue
            $result['quote'] | Should -Be $inputObject.quote
            $result['slash'] | Should -Be $inputObject.slash
            $result['multiline'] | Should -Be $inputObject.multiline
        }

        It 'escapes byte order marks as quoted scalar content' {
            $value = "foo$([char] 0xFEFF)bar"

            $yaml = ConvertTo-Yaml -InputObject $value

            $yaml.TrimEnd("`n") | Should -Be '"foo\uFEFFbar"'
            ($yaml | ConvertFrom-Yaml) | Should -Be $value
        }

        It 'emits only valid YAML characters and rejects malformed UTF-16 input' {
            $noncharacters = ([string] [char] 0xFFFE) + [char] 0xFFFF
            $yaml = ConvertTo-Yaml -InputObject $noncharacters

            $yaml | Should -Match '\\uFFFE\\uFFFF'
            ($yaml | Test-Yaml) | Should -BeTrue
            ($yaml | ConvertFrom-Yaml) | Should -Be $noncharacters
            { ConvertTo-Yaml -InputObject ([string] [char] 0xD800) } |
                Should -Throw -ExpectedMessage '*surrogate*'
        }

        It 'serializes signed, unsigned, large, decimal, and special numbers' {
            $inputObject = [ordered]@{
                signed   = [long] -9223372036854775808
                unsigned = [ulong]::MaxValue
                big      = [System.Numerics.BigInteger]::Parse('18446744073709551616')
                decimal  = [decimal] 12.50
                positive = [double]::PositiveInfinity
                negative = [double]::NegativeInfinity
                nan      = [double]::NaN
            }

            $result = ($inputObject | ConvertTo-Yaml) | ConvertFrom-Yaml -AsHashtable

            $result['signed'] | Should -Be ([long] -9223372036854775808)
            $result['unsigned'] | Should -BeOfType [System.Numerics.BigInteger]
            $result['big'] | Should -BeOfType [System.Numerics.BigInteger]
            $result['decimal'] | Should -Be 12.5
            [double]::IsPositiveInfinity($result['positive']) | Should -BeTrue
            [double]::IsNegativeInfinity($result['negative']) | Should -BeTrue
            [double]::IsNaN($result['nan']) | Should -BeTrue
        }

        It 'serializes DateTime, DateTimeOffset, and binary values with standard tags' {
            $inputObject = [ordered]@{
                utc    = [datetime]::new(2026, 7, 19, 13, 49, 21, [DateTimeKind]::Utc)
                local  = [datetimeoffset]::Parse('2026-07-19T15:49:21+02:00')
                binary = [Text.Encoding]::UTF8.GetBytes('hello')
            }

            $yaml = $inputObject | ConvertTo-Yaml
            $result = $yaml | ConvertFrom-Yaml -AsHashtable

            $yaml | Should -Match '!!timestamp'
            $yaml | Should -Match '!!binary'
            $result['utc'] | Should -BeOfType [datetimeoffset]
            $result['local'] | Should -BeOfType [datetimeoffset]
            [Text.Encoding]::UTF8.GetString($result['binary']) | Should -Be 'hello'
        }

        It 'serializes every representable DateTimeOffset boundary stably' {
            $values = @(
                [datetimeoffset]::MinValue
                [datetimeoffset]::MaxValue
                [datetimeoffset]::new(
                    [datetime]::new(1, 1, 1, 14, 0, 0),
                    [timespan]::FromHours(14)
                )
                [datetimeoffset]::new(
                    [datetime]::new(9999, 12, 31, 9, 59, 59, 999).AddTicks(9999),
                    [timespan]::FromHours(-14)
                )
            )

            foreach ($value in $values) {
                $yaml = ConvertTo-Yaml -InputObject $value
                $roundTrip = $yaml | ConvertFrom-Yaml

                ($yaml | Test-Yaml) | Should -BeTrue
                $roundTrip.UtcTicks | Should -Be $value.UtcTicks
            }
        }

        It 'classifies unrepresentable local DateTime boundaries' {
            $errors = [System.Collections.Generic.List[object]]::new()
            $successes = 0
            foreach ($value in @(
                    [datetime]::SpecifyKind([datetime]::MinValue, [DateTimeKind]::Local)
                    [datetime]::SpecifyKind([datetime]::MaxValue, [DateTimeKind]::Local)
                )) {
                try {
                    $yaml = ConvertTo-Yaml -InputObject $value
                    ($yaml | Test-Yaml) | Should -BeTrue
                    $successes++
                } catch {
                    $errors.Add($_)
                }
            }

            ($successes + $errors.Count) | Should -Be 2
            if ([TimeZoneInfo]::Local.BaseUtcOffset -ne [timespan]::Zero) {
                $errors.Count | Should -BeGreaterThan 0
            }
            foreach ($serializationError in $errors) {
                $serializationError.FullyQualifiedErrorId |
                    Should -Be 'YamlTimestampSerializationFailed,ConvertTo-Yaml'
                $serializationError.Exception.Message |
                    Should -Be 'The timestamp cannot be represented with its local or explicit UTC offset.'
            }
        }

        It 'emits aliases for repeated byte arrays and preserves their identity' {
            $bytes = [Text.Encoding]::UTF8.GetBytes('hello')
            $inputObject = [ordered]@{ first = $bytes; second = $bytes }

            $yaml = $inputObject | ConvertTo-Yaml
            $result = $yaml | ConvertFrom-Yaml -AsHashtable

            $yaml | Should -Match '&id001 !!binary'
            $yaml | Should -Match '\*id001'
            , $result['first'] | Should -BeOfType [byte[]]
            [object]::ReferenceEquals($result['first'], $result['second']) | Should -BeTrue
        }

        It 'serializes enum values numerically or by name' {
            $numeric = ([ordered]@{ day = [DayOfWeek]::Monday }) | ConvertTo-Yaml
            $named = ([ordered]@{ day = [DayOfWeek]::Monday }) |
                ConvertTo-Yaml -EnumsAsStrings

            ($numeric | ConvertFrom-Yaml).day | Should -Be 1
            ($named | ConvertFrom-Yaml).day | Should -Be 'Monday'
            ($named | ConvertFrom-Yaml).day | Should -BeOfType [string]
        }

        It 'serializes empty mappings and sequences distinctly' {
            (ConvertTo-Yaml -InputObject @()).Trim() | Should -Be '[]'
            (([ordered]@{} | ConvertTo-Yaml).Trim()) | Should -Be '{}'

            $nested = ConvertTo-Yaml -InputObject (, @())
            $nested.Trim() | Should -Be '- []'
        }

        It 'serializes a null input explicitly' {
            (ConvertTo-Yaml -InputObject $null).Trim() | Should -Be 'null'
        }

        It 'preserves complex dictionary keys through a hashtable round trip' {
            $dictionary = [System.Collections.Specialized.OrderedDictionary]::new()
            $key = [object[]]@('a', 'b')
            $dictionary.Add($key, 'value')

            $result = ($dictionary | ConvertTo-Yaml) | ConvertFrom-Yaml -AsHashtable
            $enumerator = $result.GetEnumerator()
            $null = $enumerator.MoveNext()
            $roundTripKey = $enumerator.Key

            , $roundTripKey | Should -BeOfType [object[]]
            $roundTripKey | Should -Be @('a', 'b')
            $enumerator.Value | Should -Be 'value'
        }

        It 'uses explicit keys when scalar keys exceed 1024 Unicode values' {
            $atLimit = [System.Collections.Specialized.OrderedDictionary]::new()
            $atLimit.Add(('x' * 1022), 'value')
            $overLimit = [System.Collections.Specialized.OrderedDictionary]::new()
            $overLimitKey = [char]::ConvertFromUtf32(0x1F600) * 1023
            $overLimit.Add($overLimitKey, [ordered]@{ nested = 'value' })

            $atLimitYaml = ConvertTo-Yaml -InputObject $atLimit
            $overLimitYaml = ConvertTo-Yaml -InputObject $overLimit
            $roundTrip = $overLimitYaml | ConvertFrom-Yaml -AsHashtable

            $atLimitYaml | Should -Not -Match '^\? '
            $overLimitYaml | Should -Match '^\? '
            $overLimitYaml | Should -Match '(?m)^: $'
            ($overLimitYaml | Test-Yaml) | Should -BeTrue
            $roundTrip.Contains($overLimitKey) | Should -BeTrue
            $roundTrip[$overLimitKey]['nested'] | Should -Be 'value'
        }

        It 'uses explicit keys when rendered collection keys exceed 1024 values' {
            $dictionary = [System.Collections.Specialized.OrderedDictionary]::new()
            $key = [object[]] (0..299)
            $dictionary.Add($key, 'value')

            $yaml = ConvertTo-Yaml -InputObject $dictionary
            $roundTrip = $yaml | ConvertFrom-Yaml -AsHashtable
            $enumerator = $roundTrip.GetEnumerator()
            $null = $enumerator.MoveNext()

            $yaml | Should -Match '^\? \['
            ($yaml | Test-Yaml) | Should -BeTrue
            $enumerator.Key | Should -Be $key
            $enumerator.Value | Should -Be 'value'
        }

        It 'uses explicit keys inside flow-rendered complex keys' {
            $innerKey = [System.Collections.Specialized.OrderedDictionary]::new()
            $innerKey.Add(('x' * 1025), 'inner')
            $dictionary = [System.Collections.Specialized.OrderedDictionary]::new()
            $dictionary.Add($innerKey, 'outer')

            $yaml = ConvertTo-Yaml -InputObject $dictionary

            $yaml | Should -Match '\{\? '
            ($yaml | Test-Yaml) | Should -BeTrue
            { $yaml | ConvertFrom-Yaml -AsHashtable } | Should -Not -Throw
        }

        It 'rejects dictionary keys that normalize to the same YAML value' {
            $dictionary = [System.Collections.Specialized.OrderedDictionary]::new()
            $dictionary.Add([int] 1, 'int')
            $dictionary.Add([long] 1, 'long')

            { $dictionary | ConvertTo-Yaml } |
                Should -Throw -ExpectedMessage '*normalize to the same YAML value*'
        }

        It 'normalizes finite float key fingerprints across CLR types' {
            $equal = [System.Collections.Specialized.OrderedDictionary]::new()
            $equal.Add(
                [decimal]::Parse(
                    '100000000000000000000.0',
                    [cultureinfo]::InvariantCulture
                ),
                'decimal'
            )
            $equal.Add([double] 1e20, 'double')

            { $equal | ConvertTo-Yaml } |
                Should -Throw -ExpectedMessage '*normalize to the same YAML value*'

            $different = [System.Collections.Specialized.OrderedDictionary]::new()
            $different.Add(
                [decimal]::Parse(
                    '100000000000000000001',
                    [cultureinfo]::InvariantCulture
                ),
                'decimal'
            )
            $different.Add([double] 1e20, 'double')

            { $different | ConvertTo-Yaml } | Should -Not -Throw
        }

        It 'compares unordered complex keys with ordinal case-sensitive sorting' {
            $firstKey = [System.Collections.Specialized.OrderedDictionary]::new()
            $firstKey.Add('a', 1)
            $firstKey.Add('A', 1)
            $secondKey = [System.Collections.Specialized.OrderedDictionary]::new()
            $secondKey.Add('A', 1)
            $secondKey.Add('a', 1)
            $dictionary = [System.Collections.Specialized.OrderedDictionary]::new()
            $dictionary.Add($firstKey, 'first')
            $dictionary.Add($secondKey, 'second')

            { $dictionary | ConvertTo-Yaml } |
                Should -Throw -ExpectedMessage '*normalize to the same YAML value*'
        }
    }

    Context 'Pipeline and formatting' {
        It 'collects multiple pipeline records into one sequence' {
            $yaml = 'one', 'two', 'three' | ConvertTo-Yaml
            $result = $yaml | ConvertFrom-Yaml -NoEnumerate

            $result | Should -Be @('one', 'two', 'three')
        }

        It 'uses the requested indentation and document start marker' {
            $yaml = [ordered]@{
                outer = [ordered]@{
                    inner = 'value'
                }
            } | ConvertTo-Yaml -Indent 4 -ExplicitDocumentStart

            $yaml | Should -Match '^---'
            $yaml | Should -Match '(?m)^    "inner":'
        }

        It 'normalizes output line endings to LF' {
            $yaml = [ordered]@{ one = 1; two = 2 } | ConvertTo-Yaml

            $yaml | Should -Not -Match "`r"
        }
    }

    Context 'References, metadata, and failures' {
        It 'emits aliases for repeated acyclic references' {
            $shared = [ordered]@{ value = 1 }
            $inputObject = [ordered]@{
                first  = $shared
                second = $shared
            }

            $yaml = $inputObject | ConvertTo-Yaml
            $result = $yaml | ConvertFrom-Yaml

            $yaml | Should -Match '&id001'
            $yaml | Should -Match '\*id001'
            [object]::ReferenceEquals($result.first, $result.second) | Should -BeTrue
        }

        It 'does not leak PowerShell type metadata' {
            $inputObject = [pscustomobject]@{ name = 'Ada' }
            $inputObject.PSObject.TypeNames.Insert(0, 'Secret.Application.Type')

            $yaml = $inputObject | ConvertTo-Yaml

            $yaml | Should -Not -Match 'Secret\.Application\.Type'
            $yaml | Should -Not -Match 'PSTypeNames'
            ($yaml | ConvertFrom-Yaml).name | Should -Be 'Ada'
        }

        It 'serializes explicit PSObject note properties without adapted metadata' {
            $inputObject = [object]::new()
            $inputObject | Add-Member -MemberType NoteProperty -Name name -Value 'Ada'

            $yaml = $inputObject | ConvertTo-Yaml
            $result = $yaml | ConvertFrom-Yaml

            $result.name | Should -Be 'Ada'
            $yaml | Should -Not -Match 'GetType'
            $yaml | Should -Not -Match 'ToString'
        }

        It 'rejects cyclic structures specifically' {
            $cycle = [System.Collections.ArrayList]::new()
            $cycle.Add($cycle)

            { ConvertTo-Yaml -InputObject $cycle } |
                Should -Throw -ExpectedMessage '*cycle was detected*'
        }

        It 'rejects unsupported runtime objects instead of stringifying them' {
            { ConvertTo-Yaml -InputObject ([uri] 'https://example.com') } |
                Should -Throw -ExpectedMessage "*System.Uri*not supported*"
        }

        It 'rejects non-data PSCustomObject properties' {
            $inputObject = [pscustomobject]@{ name = 'Ada' }
            $inputObject | Add-Member -MemberType ScriptProperty -Name Computed -Value { 'value' }

            { $inputObject | ConvertTo-Yaml } |
                Should -Throw -ExpectedMessage "*Computed*not a note property*"
        }

        It 'rejects attached note properties on arrays and dictionaries' {
            $array = [object[]] @(1, 2)
            Add-Member -InputObject $array -MemberType NoteProperty -Name metadata -Value 'lossy'
            $dictionary = [ordered]@{ value = 1 }
            Add-Member -InputObject $dictionary -MemberType NoteProperty -Name metadata -Value 'lossy'

            { ConvertTo-Yaml -InputObject $array } |
                Should -Throw -ExpectedMessage '*combines collection data with attached note properties*'
            { ConvertTo-Yaml -InputObject $dictionary } |
                Should -Throw -ExpectedMessage '*combines collection data with attached note properties*'
        }

        It 'rejects attached note properties on scalar values' {
            $value = [psobject] 42
            Add-Member -InputObject $value -MemberType NoteProperty -Name metadata -Value 'lossy'

            { ConvertTo-Yaml -InputObject $value } |
                Should -Throw -ExpectedMessage '*combines scalar data with attached note properties*'
        }

        It 'preserves the sign of IEEE negative zero across serialization' {
            $negativeZero = [BitConverter]::Int64BitsToDouble([long]::MinValue)
            $yaml = ConvertTo-Yaml -InputObject $negativeZero
            $result = $yaml | ConvertFrom-Yaml

            $yaml.Trim() | Should -Be '-0.0'
            ([decimal]::GetBits($result)[3] -band [int]::MinValue) |
                Should -Be ([int]::MinValue)
        }

        It 'enforces depth, node, and scalar limits without truncating' {
            $nested = [ordered]@{ a = [ordered]@{ b = [ordered]@{ c = 1 } } }

            { $nested | ConvertTo-Yaml -Depth 2 } |
                Should -Throw -ExpectedMessage '*configured depth limit of 2*'
            { @(1, 2) | ConvertTo-Yaml -MaxNodes 2 } |
                Should -Throw -ExpectedMessage '*configured limit of 2 nodes*'
            { 'long' | ConvertTo-Yaml -MaxScalarLength 3 } |
                Should -Throw -ExpectedMessage '*configured limit of 3 characters*'
        }

        It 'stops infinite pipelines at the node budget' {
            $script:YamlTestPipelineCount = 0

            { Get-YamlTestInfinitePipeline | ConvertTo-Yaml -MaxNodes 4 } |
                Should -Throw -ExpectedMessage '*configured limit of 4 nodes*'
            $script:YamlTestPipelineCount | Should -BeLessOrEqual 4
        }

        It 'stops infinite pipelines at the first oversized scalar' {
            $script:YamlTestPipelineCount = 0

            $conversion = {
                Get-YamlTestInfinitePipeline -Item 'long' |
                    ConvertTo-Yaml -MaxScalarLength 3
            }
            $conversion | Should -Throw -ExpectedMessage '*configured limit of 3 characters*'
            $script:YamlTestPipelineCount | Should -Be 1
        }

        It 'stops and disposes infinite enumerables at the node budget' {
            $source = [YamlTests.InfiniteEnumerable]::new()

            { ConvertTo-Yaml -InputObject $source -MaxNodes 4 } |
                Should -Throw -ExpectedMessage '*configured limit of 4 nodes*'
            $source.MoveNextCount | Should -Be 4
            $source.DisposeCount | Should -Be 1
        }

        It 'shares the node budget while buffering nested enumerables' {
            $children = [System.Collections.Generic.List[object]]::new()
            $sources = [System.Collections.Generic.List[object]]::new()
            foreach ($index in 1..9) {
                $child = [YamlTests.OneShotEnumerable]::new([object[]] (1..9))
                $children.Add($child)
                $sources.Add($child)
            }
            $root = [YamlTests.OneShotEnumerable]::new([object[]] $children.ToArray())
            $sources.Add($root)

            { ConvertTo-Yaml -InputObject $root -MaxNodes 20 } |
                Should -Throw -ExpectedMessage '*configured limit of 20 nodes*'
            ($sources | Measure-Object -Property MoveNextCount -Sum).Sum |
                Should -BeLessOrEqual 22
            ($sources | Measure-Object -Property DisposeCount -Sum).Sum | Should -Be 3
        }

        It 'stops and disposes enumerables at the first oversized scalar' {
            $source = [YamlTests.InfiniteEnumerable]::new('long')

            { ConvertTo-Yaml -InputObject $source -MaxScalarLength 3 } |
                Should -Throw -ExpectedMessage '*configured limit of 3 characters*'
            $source.MoveNextCount | Should -Be 1
            $source.DisposeCount | Should -Be 1
        }

        It 'does not re-enumerate repeated references' {
            $source = [YamlTests.OneShotEnumerable]::new([object[]] @(1, 2))
            $inputObject = [ordered]@{ first = $source; second = $source }

            $yaml = ConvertTo-Yaml -InputObject $inputObject

            $source.GetEnumeratorCount | Should -Be 1
            $source.DisposeCount | Should -Be 1
            $yaml | Should -Match '&id001'
            $yaml | Should -Match '\*id001'
        }

        It 'prechecks Base64 output before allocating the encoded scalar' {
            $bytes = [byte[]] @(1, 2, 3)

            { ConvertTo-Yaml -InputObject $bytes -MaxScalarLength 3 } |
                Should -Throw -ExpectedMessage '*configured limit of 3 characters*'
        }

        It 'supports the public maximum depth and rejects the next level specifically' {
            $atLimit = [ordered]@{}
            $current = $atLimit
            for ($level = 1; $level -lt 127; $level++) {
                $next = [ordered]@{}
                $current['nested'] = $next
                $current = $next
            }
            $current['value'] = 1

            { ConvertTo-Yaml -InputObject $atLimit -Depth 128 } | Should -Not -Throw

            $overLimit = [ordered]@{ nested = $atLimit }
            { ConvertTo-Yaml -InputObject $overLimit -Depth 128 } |
                Should -Throw -ExpectedMessage '*configured depth limit of 128*'
        }

        It 'enforces the scalar limit for every emitted scalar kind' {
            $bigInteger = [System.Numerics.BigInteger]::Parse('12345')

            { ConvertTo-Yaml -InputObject $null -MaxScalarLength 3 } |
                Should -Throw -ExpectedMessage '*configured limit of 3 characters*'
            { ConvertTo-Yaml -InputObject $true -MaxScalarLength 3 } |
                Should -Throw -ExpectedMessage '*configured limit of 3 characters*'
            { ConvertTo-Yaml -InputObject $bigInteger -MaxScalarLength 4 } |
                Should -Throw -ExpectedMessage '*configured limit of 4 characters*'
            { ConvertTo-Yaml -InputObject ([decimal] 12.5) -MaxScalarLength 3 } |
                Should -Throw -ExpectedMessage '*configured limit of 3 characters*'
            { ConvertTo-Yaml -InputObject ([double]::PositiveInfinity) -MaxScalarLength 3 } |
                Should -Throw -ExpectedMessage '*configured limit of 3 characters*'
            { ConvertTo-Yaml -InputObject ([datetime]::UtcNow) -MaxScalarLength 10 } |
                Should -Throw -ExpectedMessage '*configured limit of 10 characters*'
            { ConvertTo-Yaml -InputObject ([byte[]] @(1, 2, 3)) -MaxScalarLength 3 } |
                Should -Throw -ExpectedMessage '*configured limit of 3 characters*'
            { ConvertTo-Yaml -InputObject ([DayOfWeek]::Monday) -EnumsAsStrings -MaxScalarLength 5 } |
                Should -Throw -ExpectedMessage '*configured limit of 5 characters*'
        }
    }
}
