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
}

Describe 'ConvertFrom-Yaml' {
    Context 'YAML 1.2 core schema' {
        It 'resolves <Text> as <Type>' -ForEach @(
            @{ Text = ''; Type = 'null'; Expected = $null }
            @{ Text = '~'; Type = 'null'; Expected = $null }
            @{ Text = 'null'; Type = 'null'; Expected = $null }
            @{ Text = 'Null'; Type = 'null'; Expected = $null }
            @{ Text = 'NULL'; Type = 'null'; Expected = $null }
            @{ Text = 'true'; Type = 'Boolean'; Expected = $true }
            @{ Text = 'True'; Type = 'Boolean'; Expected = $true }
            @{ Text = 'TRUE'; Type = 'Boolean'; Expected = $true }
            @{ Text = 'false'; Type = 'Boolean'; Expected = $false }
            @{ Text = 'False'; Type = 'Boolean'; Expected = $false }
            @{ Text = 'FALSE'; Type = 'Boolean'; Expected = $false }
            @{ Text = '01'; Type = 'Int32'; Expected = 1 }
            @{ Text = '0o14'; Type = 'Int32'; Expected = 12 }
            @{ Text = '0xC'; Type = 'Int32'; Expected = 12 }
            @{ Text = '1.23015e+3'; Type = 'Double'; Expected = 1230.15 }
        ) {
            $result = "value: $Text" | ConvertFrom-Yaml

            $result.value | Should -Be $Expected
            if ($Type -ne 'null') {
                $result.value.GetType().Name | Should -Be $Type
            }
        }

        It 'keeps YAML 1.1-only implicit values and timestamps as strings' {
            $result = @'
yes: yes
no: NO
on: on
off: Off
timestamp: 2001-12-15T02:59:43.1Z
'@ | ConvertFrom-Yaml

            $result.yes | Should -BeOfType [string]
            $result.no | Should -BeOfType [string]
            $result.on | Should -BeOfType [string]
            $result.off | Should -BeOfType [string]
            $result.timestamp | Should -BeOfType [string]
        }

        It 'keeps quoted and block scalars as strings' {
            $result = @'
quoted: "true"
literal: |
  42
folded: >
  null
  text
'@ | ConvertFrom-Yaml

            $result.quoted | Should -Be 'true'
            $result.quoted | Should -BeOfType [string]
            $result.literal | Should -Be "42`n"
            $result.folded | Should -Be "null text`n"
        }

        It 'uses BigInteger beyond Int64' {
            $result = 'value: 9223372036854775808' | ConvertFrom-Yaml

            $result.value | Should -BeOfType [System.Numerics.BigInteger]
            $result.value.ToString() | Should -Be '9223372036854775808'
        }
    }

    Context 'Mappings and sequences' {
        It 'returns ordinary mappings as ordered PSCustomObject properties' {
            $result = "zebra: 1`napple: 2" | ConvertFrom-Yaml

            $result | Should -BeOfType [pscustomobject]
            @($result.PSObject.Properties.Name) | Should -Be @('zebra', 'apple')
        }

        It 'returns recursive ordered dictionaries with AsHashtable' {
            $result = "outer:`n  inner: value" | ConvertFrom-Yaml -AsHashtable

            $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $result['outer'] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $result['outer']['inner'] | Should -Be 'value'
        }

        It 'preserves a complex key with AsHashtable' {
            $result = "? [Detroit Tigers, Chicago Cubs]`n: 2001-07-23" |
                ConvertFrom-Yaml -AsHashtable
            $enumerator = $result.GetEnumerator()
            $null = $enumerator.MoveNext()
            $key = $enumerator.Key

            , $key | Should -BeOfType [object[]]
            $key | Should -Be @('Detroit Tigers', 'Chicago Cubs')
            $enumerator.Value | Should -Be '2001-07-23'
        }

        It 'fails rather than losing a complex key in PSCustomObject mode' {
            { "? [a, b]`n: value" | ConvertFrom-Yaml } |
                Should -Throw -ExpectedMessage '*Use -AsHashtable*'
        }

        It 'fails on case-insensitive property collisions but preserves them with AsHashtable' {
            { "Name: one`nname: two" | ConvertFrom-Yaml } |
                Should -Throw -ExpectedMessage '*case-insensitive property collision*'

            $result = "Name: one`nname: two" | ConvertFrom-Yaml -AsHashtable
            $result.Count | Should -Be 2
            $result['Name'] | Should -Be 'one'
            $result['name'] | Should -Be 'two'
        }

        It 'enumerates only top-level sequences by default' {
            $result = "- one`n- two" | ConvertFrom-Yaml

            @($result) | Should -Be @('one', 'two')
        }

        It 'preserves a top-level sequence with NoEnumerate' {
            $result = "- one`n- two" | ConvertFrom-Yaml -NoEnumerate

            , $result | Should -BeOfType [object[]]
            $result | Should -Be @('one', 'two')
        }
    }

    Context 'Streams and pipeline input' {
        It 'joins pipeline lines as one YAML stream' {
            $result = 'name: Ada', 'active: true' | ConvertFrom-Yaml

            $result.name | Should -Be 'Ada'
            $result.active | Should -BeTrue
        }

        It 'returns every document separately' {
            $result = @(
                "---`nname: first`n...`n---`nname: second" | ConvertFrom-Yaml
            )

            $result.Count | Should -Be 2
            $result[0].name | Should -Be 'first'
            $result[1].name | Should -Be 'second'
        }
    }

    Context 'Tags, anchors, and aliases' {
        It 'constructs explicit standard scalar tags safely' {
            $result = @'
text: !!str 42
number: !!int "42"
binary: !!binary SGVsbG8=
offset: !!timestamp 2026-07-19T15:49:21+02:00
date: !!timestamp 2026-07-19
'@ | ConvertFrom-Yaml

            $result.text | Should -BeOfType [string]
            $result.number | Should -BeOfType [int]
            [Text.Encoding]::UTF8.GetString($result.binary) | Should -Be 'Hello'
            $result.offset | Should -BeOfType [datetimeoffset]
            $result.date | Should -BeOfType [datetime]
        }

        It 'treats unknown application tags as neutral non-activating metadata' {
            $result = @'
scalar: !System.Management.Automation.PSObject 42
mapping: !<tag:example.test,2026:object>
  name: safe
'@ | ConvertFrom-Yaml

            $result.scalar | Should -Be '42'
            $result.scalar | Should -BeOfType [string]
            $result.mapping.name | Should -Be 'safe'
        }

        It 'preserves repeated collection references' {
            $result = @'
source: &source
  value: 1
copy: *source
'@ | ConvertFrom-Yaml

            [object]::ReferenceEquals($result.source, $result.copy) | Should -BeTrue
        }

        It 'constructs recursive aliases without recursing forever' {
            $result = '&root [*root]' | ConvertFrom-Yaml -NoEnumerate

            [object]::ReferenceEquals($result, $result[0]) | Should -BeTrue
        }

        It 'constructs set, ordered-map, and pairs tags safely' {
            $set = "!!set`n? one`n? two" | ConvertFrom-Yaml
            $orderedMap = "!!omap`n- one: 1`n- two: 2" | ConvertFrom-Yaml
            $pairs = "!!pairs`n- one: 1`n- one: 2" | ConvertFrom-Yaml -NoEnumerate

            $set | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $set.Count | Should -Be 2
            $orderedMap | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            @($orderedMap.Keys) | Should -Be @('one', 'two')
            $pairs.Count | Should -Be 2
            $pairs[0] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        }

        It 'caches binary scalar construction and preserves binary alias identity' {
            $result = "first: &bytes !!binary SGVsbG8=`nsecond: *bytes" |
                ConvertFrom-Yaml -AsHashtable

            , $result['first'] | Should -BeOfType [byte[]]
            [object]::ReferenceEquals($result['first'], $result['second']) | Should -BeTrue
        }

        It 'constructs ordered mappings with complex keys without re-enumerating them' {
            $result = "!!omap`n- ? [a, b]`n  : value" | ConvertFrom-Yaml -AsHashtable
            $enumerator = $result.GetEnumerator()
            $null = $enumerator.MoveNext()

            , $enumerator.Key | Should -BeOfType [object[]]
            $enumerator.Key | Should -Be @('a', 'b')
            $enumerator.Value | Should -Be 'value'
        }

        It 'matches standard tags ordinally and treats case variants as unknown' {
            $result = "integer: !!INT 12`nset: !!SET {one: null}" |
                ConvertFrom-Yaml -AsHashtable

            $result['integer'] | Should -BeOfType [string]
            $result['integer'] | Should -Be '12'
            $result['set'] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $result['set']['one'] | Should -BeNullOrEmpty
        }

        It 'uses deterministic UTC semantics for zone-less explicit timestamps' {
            $result = @'
offset: !!timestamp 2001-12-14T21:59:43.1+5:30
wholeHour: !!timestamp 2001-12-14T21:59:43+5
zoneLess: !!timestamp 2001-12-14T21:59:43.1
date: !!timestamp 2001-12-14
'@ | ConvertFrom-Yaml

            $result.offset | Should -BeOfType [datetimeoffset]
            $result.offset.Offset | Should -Be ([timespan]::FromHours(5.5))
            $result.wholeHour | Should -BeOfType [datetimeoffset]
            $result.wholeHour.Offset | Should -Be ([timespan]::FromHours(5))
            $result.zoneLess | Should -BeOfType [datetime]
            $result.zoneLess.Kind | Should -Be ([DateTimeKind]::Utc)
            $result.date.Kind | Should -Be ([DateTimeKind]::Utc)
        }
    }

    Context 'Validation and limits' {
        It 'rejects duplicate scalar, canonical numeric, and complex keys' {
            { "key: one`nkey: two" | ConvertFrom-Yaml } | Should -Throw
            { "1: one`n01: two" | ConvertFrom-Yaml -AsHashtable } | Should -Throw
            { "1.0: one`n1.00: two" | ConvertFrom-Yaml -AsHashtable } | Should -Throw
            { "1.0: one`n1e0: two" | ConvertFrom-Yaml -AsHashtable } | Should -Throw
            { "? [a, b]`n: one`n? [a, b]`n: two" | ConvertFrom-Yaml -AsHashtable } |
                Should -Throw
            { "? {a: 1, A: 1}`n: one`n? {A: 1, a: 1}`n: two" | ConvertFrom-Yaml -AsHashtable } |
                Should -Throw
        }

        It 'rejects equivalent offset timestamps as duplicate keys' {
            $yaml = @'
? !!timestamp 2001-12-15T02:59:43.1Z
: one
? !!timestamp 2001-12-14T21:59:43.1-05:00
: two
'@

            { $yaml | ConvertFrom-Yaml -AsHashtable } | Should -Throw
            ($yaml | Test-Yaml) | Should -BeFalse
        }

        It 'rejects equivalent zone-less and UTC timestamp keys' {
            $yaml = @'
? !!timestamp 2001-12-15T02:59:43.1
: one
? !!timestamp 2001-12-15T02:59:43.1Z
: two
'@

            { $yaml | ConvertFrom-Yaml -AsHashtable } | Should -Throw
            ($yaml | Test-Yaml) | Should -BeFalse
        }

        It 'rejects finite floating-point values outside the supported range' {
            { 'value: 1e9999' | ConvertFrom-Yaml } |
                Should -Throw -ExpectedMessage '*outside the supported range*'
            ('value: 1e9999' | Test-Yaml) | Should -BeFalse
        }

        It 'rejects undefined aliases' {
            { 'value: *missing' | ConvertFrom-Yaml } | Should -Throw
        }

        It 'enforces depth, node, alias, and scalar limits' {
            { "a:`n  b:`n    c: value" | ConvertFrom-Yaml -Depth 2 } | Should -Throw
            { "[one, two]" | ConvertFrom-Yaml -MaxNodes 2 } | Should -Throw
            { "a: &a value`nb: *a" | ConvertFrom-Yaml -MaxAliases 0 } | Should -Throw
            { 'value: long' | ConvertFrom-Yaml -MaxScalarLength 4 } | Should -Throw
        }

        It 'enforces tag and numeric limits before expensive construction' {
            $prefix = 'x' * 2000
            $tagged = "%TAG ! tag:example.test,$prefix`n---`n- !value one"
            $manyTags = "%TAG ! tag:e,`n---`n- !a one`n- !b two"
            $largeInteger = '9' * 5000

            ($tagged | Test-Yaml -MaxTagLength 1024) | Should -BeFalse
            ($manyTags | Test-Yaml -MaxTagLength 1024 -MaxTotalTagLength 13) | Should -BeFalse
            ($largeInteger | Test-Yaml -MaxNumericLength 4096) | Should -BeFalse
            { $largeInteger | ConvertFrom-Yaml -MaxNumericLength 4096 } | Should -Throw
        }

        It 'bounds expanded-tag storage and rejects huge numerics promptly' {
            $prefix = 'x' * 20000
            $taggedItems = 1..500 | ForEach-Object { '- !e!value item' }
            $tagAmplification = (
                @("%TAG !e! tag:example.test,$prefix", '---') + $taggedItems
            ) -join "`n"
            $hugeInteger = '9' * 320000

            ($tagAmplification | Test-Yaml -MaxTagLength 25000) |
                Should -BeFalse
            $testResult = $null
            $testDuration = Measure-Command {
                $testResult = $hugeInteger | Test-Yaml -MaxNumericLength 4096
            }
            $convertFailed = $false
            $convertDuration = Measure-Command {
                try {
                    $null = $hugeInteger |
                        ConvertFrom-Yaml -MaxNumericLength 4096
                } catch {
                    $convertFailed = $true
                }
            }

            $testResult | Should -BeFalse
            $convertFailed | Should -BeTrue
            $testDuration.TotalSeconds | Should -BeLessThan 2
            $convertDuration.TotalSeconds | Should -BeLessThan 2
        }

        It 'preserves finite decimal precision and IEEE negative zero' {
            $result = @'
precise: 0.1234567890123456789012345678
negativeZero: -0.0
'@ | ConvertFrom-Yaml

            $result.precise | Should -BeOfType [decimal]
            $result.precise.ToString([cultureinfo]::InvariantCulture) |
                Should -Be '0.1234567890123456789012345678'
            $result.negativeZero | Should -BeOfType [decimal]
            ([decimal]::GetBits($result.negativeZero)[3] -band [int]::MinValue) |
                Should -Be ([int]::MinValue)
        }

        It 'preserves flow-looking text inside block scalars without repairing it' {
            $result = "value: |`n  [`n    keep`n" | ConvertFrom-Yaml

            $result.value | Should -Be "[`n  keep`n"
        }

        It 'applies block scalar indentation, folding, and chomping exactly' {
            ("|2`n  text`n" | ConvertFrom-Yaml) | Should -Be "text`n"
            (">`n  one`n`n  two`n" | ConvertFrom-Yaml) | Should -Be "one`ntwo`n"
            ("|+`n  text`n`n" | ConvertFrom-Yaml) | Should -Be "text`n`n"
        }

        It 'applies YAML flow folding to multiline quoted scalars' {
            ('"one' + "`n`n  two`n  " + '"') | ConvertFrom-Yaml |
                Should -Be "one`ntwo "
        }

        It 'rejects raw non-printable characters and unpaired surrogates' {
            { ConvertFrom-Yaml -Yaml ("value: x{0}" -f [char] 0) } | Should -Throw
            { ConvertFrom-Yaml -Yaml ("value: x{0}" -f [char] 1) } | Should -Throw
            { ConvertFrom-Yaml -Yaml ("value: x{0}" -f [char] 11) } | Should -Throw
            { ConvertFrom-Yaml -Yaml ("value: x{0}" -f [char] 0xD800) } | Should -Throw
        }
    }
}
