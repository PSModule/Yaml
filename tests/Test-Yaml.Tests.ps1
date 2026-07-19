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
