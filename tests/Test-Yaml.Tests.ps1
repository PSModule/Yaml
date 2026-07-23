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

Describe 'Test-Yaml' {
    It 'returns true for valid YAML and an empty stream' {
        ('name: Ada' | Test-Yaml) | Should -BeTrue
        ('' | Test-Yaml) | Should -BeTrue
    }

    It 'joins pipeline lines consistently with ConvertFrom-Yaml' {
        ('name: Ada', 'items: [one, two]' | Test-Yaml) | Should -BeTrue
    }

    It 'returns false for malformed syntax' {
        ('items: [one, two' | Test-Yaml) | Should -BeFalse
        ("[ key`n  : value ]" | Test-Yaml) | Should -BeFalse
        ("{ key`n  : value }" | Test-Yaml) | Should -BeTrue
        ((('k' * 1025) + ': value') | Test-Yaml) | Should -BeFalse
        ("%YAML 1.1#invalid`n---`nvalue" | Test-Yaml) | Should -BeFalse
        ('"\UFFFFFFFF"' | Test-Yaml) | Should -BeFalse
        ('@reserved' | Test-Yaml) | Should -BeFalse
        ("key: first`n  nested: value" | Test-Yaml) | Should -BeFalse
        ("a: &a value`nb: !foo *a" | Test-Yaml) | Should -BeFalse
    }

    It 'enforces implicit-key line and Unicode scalar limits' {
        $emoji = [char]::ConvertFromUtf32(0x1F600)

        ("['multi`n  line': value]" | Test-Yaml) | Should -BeFalse
        ("[multi`n  line: value]" | Test-Yaml) | Should -BeFalse

        foreach ($case in @(
                @{ Key = 'k' * 1024; Valid = $true }
                @{ Key = 'k' * 1025; Valid = $false }
                @{ Key = "'$('k' * 1022)'"; Valid = $true }
                @{ Key = "'$('k' * 1023)'"; Valid = $false }
                @{ Key = '"' + ('\u0061' * 170) + 'aa"'; Valid = $true }
                @{ Key = '"' + ('\u0061' * 170) + 'aaa"'; Valid = $false }
                @{ Key = '!local ' + ('k' * 1017); Valid = $true }
                @{ Key = '!local ' + ('k' * 1018); Valid = $false }
            )) {
            foreach ($yaml in @(
                    "[$($case.Key)`: value]",
                    "{$($case.Key)`: value}"
                )) {
                ($yaml | Test-Yaml) | Should -Be $case.Valid
            }
        }

        foreach ($length in @(513, 1024, 1025)) {
            $key = $emoji * $length
            ("{$key`: value}" | Test-Yaml) |
                Should -Be ($length -le 1024)
        }

    }

    It 'resolves non-specific tags before comparing representation keys' {
        ("! x: one`n!!str x: two" | Test-Yaml) | Should -BeFalse
        ("? ! [x]`n: one`n? !!seq [x]`n: two" | Test-Yaml) | Should -BeFalse
    }

    It 'accepts multiline keys in flow mappings' {
        ("{'multi`n  line': value}" | Test-Yaml) | Should -BeTrue
        ("{multi`n  line: value}" | Test-Yaml) | Should -BeTrue
    }

    It 'validates tag directives, tag tokens, and alias properties' {
        ("%TAG !! tag:example.com,2000:app/`n---`n!!int value" | Test-Yaml) |
            Should -BeTrue
        ("%FOO-BAR baz`n---`nvalue" | Test-Yaml) | Should -BeTrue
        ("%FOO:B alpha-beta p#q`n---`nvalue" | Test-Yaml) | Should -BeTrue
        ("%TAG ! tag:first/`n%TAG ! tag:second/`n---`n!value data" | Test-Yaml) |
            Should -BeFalse
        ("% FOO baz`n---`nvalue" | Test-Yaml) | Should -BeFalse
        ("%`n---`nvalue" | Test-Yaml) | Should -BeFalse
        ('!foo%GG value' | Test-Yaml) | Should -BeFalse
        ('!foo\bar value' | Test-Yaml) | Should -BeFalse
        ('!<tag:example.test,2026:foo\bar> value' | Test-Yaml) | Should -BeFalse
        ('!! value' | Test-Yaml) | Should -BeFalse
        ('!<tag:example.test,2026:bad tag> value' | Test-Yaml) | Should -BeFalse
        ('!<tag:example.test,2026:a;b/c?d@e&f=g+h$i,j_k.l~m*n''o(p)[q]%21> value' |
            Test-Yaml) | Should -BeTrue
        ("a: &a value`nb: &b *a" | Test-Yaml) | Should -BeFalse
    }

    It 'recognizes document markers only at column zero' {
        ("key:`n  ---" | Test-Yaml) | Should -BeTrue
        ("key:`n  ..." | Test-Yaml) | Should -BeTrue
    }

    It 'returns false for duplicate mapping keys' {
        ("key: one`nkey: two" | Test-Yaml) | Should -BeFalse
        ("1: one`n01: two" | Test-Yaml) | Should -BeFalse
    }

    It 'includes effective tags in mapping-key equality' {
        ("!foo x: one`n!bar x: two" | Test-Yaml) | Should -BeTrue
        ("!foo x: one`n!foo x: two" | Test-Yaml) | Should -BeFalse
        (@'
? !foo [x]
: one
? !bar [x]
: two
'@ | Test-Yaml) | Should -BeTrue
        (@'
? !foo {x: y}
: one
? !bar {x: y}
: two
'@ | Test-Yaml) | Should -BeTrue
    }

    It 'accepts complex keys even though default object projection cannot' {
        ("? [a, b]`n: value" | Test-Yaml) | Should -BeTrue
    }

    It 'returns false when a configured safety limit is exceeded' {
        ("a:`n  b:`n    c: value" | Test-Yaml -Depth 2) | Should -BeFalse
        ("[one, two]" | Test-Yaml -MaxNodes 2) | Should -BeFalse
        ("a: &a value`nb: *a" | Test-Yaml -MaxAliases 0) | Should -BeFalse
        ('value: long' | Test-Yaml -MaxScalarLength 4) | Should -BeFalse
    }

    It 'accepts the public maximum depth and rejects the next level as YAML data' {
        $atLimit = ('[' * 127) + 'null' + (']' * 127)
        $overLimit = ('[' * 128) + 'null' + (']' * 128)

        ($atLimit | Test-Yaml -Depth 128 -MaxNodes 200) | Should -BeTrue
        ($overLimit | Test-Yaml -Depth 128 -MaxNodes 200) | Should -BeFalse
    }

    It 'uses fixed-size fingerprints for an alias DAG' {
        $lines = [System.Collections.Generic.List[string]]::new()
        $lines.Add('base: &a0 [x, x]')
        for ($level = 1; $level -le 12; $level++) {
            $lines.Add(('level{0}: &a{0} [*a{1}, *a{1}]' -f $level, ($level - 1)))
        }
        $lines.Add('? *a12')
        $lines.Add(': value')
        $yaml = $lines -join "`n"

        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $result = Test-Yaml -Yaml $yaml -MaxNodes 100 -MaxAliases 100
        $stopwatch.Stop()

        $fingerprintLengths = @(Get-TestYamlFingerprintLength -Yaml $yaml)

        $result | Should -BeTrue
        $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 5
        @($fingerprintLengths | Where-Object { $_ -ne 44 }).Count | Should -Be 0
    }

    It 'does not swallow an unexpected runtime failure' {
        $loadedModule = Get-Module -Name Yaml | Select-Object -First 1
        if ($null -eq $loadedModule) {
            Mock Read-YamlStream {
                throw [System.InvalidOperationException]::new('unexpected runtime failure')
            }
        } else {
            Mock Read-YamlStream -ModuleName $loadedModule.Name {
                throw [System.InvalidOperationException]::new('unexpected runtime failure')
            }
        }

        { 'name: Ada' | Test-Yaml } |
            Should -Throw -ExpectedMessage '*unexpected runtime failure*'
    }
}
