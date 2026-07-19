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
    }

    It 'returns false for duplicate mapping keys' {
        ("key: one`nkey: two" | Test-Yaml) | Should -BeFalse
        ("1: one`n01: two" | Test-Yaml) | Should -BeFalse
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

        $document = @(Read-YamlStreamCore -Yaml $yaml -Depth 100 -MaxNodes 100 -MaxAliases 100 `
                -MaxScalarLength 1048576)[0]
        $cache = [System.Collections.Generic.Dictionary[int, string]]::new()
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            Test-YamlNodeGraph -Node $document -Visited ([System.Collections.Generic.HashSet[int]]::new()) `
                -FingerprintCache $cache -FingerprintHasher $hasher
        } finally {
            $hasher.Dispose()
        }

        $result | Should -BeTrue
        $stopwatch.Elapsed.TotalSeconds | Should -BeLessThan 5
        @($cache.Values | Where-Object Length -NE 44).Count | Should -Be 0
    }

    It 'does not swallow an unexpected runtime failure' {
        Mock Read-YamlStream {
            throw [System.InvalidOperationException]::new('unexpected runtime failure')
        }

        { 'name: Ada' | Test-Yaml } |
            Should -Throw -ExpectedMessage '*unexpected runtime failure*'
    }
}
