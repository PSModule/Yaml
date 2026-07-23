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

Describe 'YAML 1.2.2 Chapter 2 examples' {
    BeforeAll {
        $chapterPath = Join-Path $PSScriptRoot 'fixtures\yaml-spec-1.2.2\chapter-02'
    }

    It 'accepts and constructs Example <Number>: <Name>' -ForEach @(
        @{ Number = '2.01'; Name = 'Sequence of Scalars' }
        @{ Number = '2.02'; Name = 'Mapping Scalars to Scalars' }
        @{ Number = '2.03'; Name = 'Mapping Scalars to Sequences' }
        @{ Number = '2.04'; Name = 'Sequence of Mappings' }
        @{ Number = '2.05'; Name = 'Sequence of Sequences' }
        @{ Number = '2.06'; Name = 'Mapping of Mappings' }
        @{ Number = '2.07'; Name = 'Two Documents in a Stream' }
        @{ Number = '2.08'; Name = 'Play by Play Feed' }
        @{ Number = '2.09'; Name = 'Document with Comments' }
        @{ Number = '2.10'; Name = 'Anchor and Alias' }
        @{ Number = '2.11'; Name = 'Mapping between Sequences' }
        @{ Number = '2.12'; Name = 'Compact Nested Mapping' }
        @{ Number = '2.13'; Name = 'Literal Scalar' }
        @{ Number = '2.14'; Name = 'Folded Scalar' }
        @{ Number = '2.15'; Name = 'Folded More-indented Lines' }
        @{ Number = '2.16'; Name = 'Indentation Scope' }
        @{ Number = '2.17'; Name = 'Quoted Scalars' }
        @{ Number = '2.18'; Name = 'Multi-line Flow Scalars' }
        @{ Number = '2.19'; Name = 'Integers' }
        @{ Number = '2.20'; Name = 'Floating Point' }
        @{ Number = '2.21'; Name = 'Miscellaneous Scalars' }
        @{ Number = '2.22'; Name = 'Timestamps' }
        @{ Number = '2.23'; Name = 'Explicit Tags' }
        @{ Number = '2.24'; Name = 'Global Tags' }
        @{ Number = '2.25'; Name = 'Unordered Set' }
        @{ Number = '2.26'; Name = 'Ordered Mapping' }
        @{ Number = '2.27'; Name = 'Invoice' }
        @{ Number = '2.28'; Name = 'Log File' }
    ) {
        $yaml = Get-Content -Path (Join-Path $chapterPath "$Number.yaml") -Raw

        ($yaml | Test-Yaml) | Should -BeTrue
        { $yaml | ConvertFrom-Yaml -AsHashtable -NoEnumerate } | Should -Not -Throw
    }

    It 'constructs the block and flow collection examples' {
        $sequence = Get-Content -Path (Join-Path $chapterPath '2.01.yaml') -Raw |
            ConvertFrom-Yaml -NoEnumerate
        $mapping = Get-Content -Path (Join-Path $chapterPath '2.06.yaml') -Raw |
            ConvertFrom-Yaml

        $sequence | Should -Be @('Mark McGwire', 'Sammy Sosa', 'Ken Griffey')
        $mapping.'Mark McGwire'.hr | Should -Be 65
        $mapping.'Sammy Sosa'.avg | Should -Be 0.288
    }

    It 'constructs multi-document streams from Examples 2.7, 2.8, and 2.28' {
        $ranking = @(
            Get-Content -Path (Join-Path $chapterPath '2.07.yaml') -Raw |
                ConvertFrom-Yaml -NoEnumerate
        )
        $feed = @(
            Get-Content -Path (Join-Path $chapterPath '2.08.yaml') -Raw |
                ConvertFrom-Yaml
        )
        $log = @(
            Get-Content -Path (Join-Path $chapterPath '2.28.yaml') -Raw |
                ConvertFrom-Yaml
        )

        $ranking.Count | Should -Be 2
        $feed.Count | Should -Be 2
        $feed[1].action | Should -Be 'grand slam'
        $log.Count | Should -Be 3
        $log[2].Stack[1].code | Should -Be 'foo = bar'
    }

    It 'constructs literal, folded, quoted, and multi-line scalars' {
        $literal = Get-Content -Path (Join-Path $chapterPath '2.13.yaml') -Raw |
            ConvertFrom-Yaml
        $folded = Get-Content -Path (Join-Path $chapterPath '2.14.yaml') -Raw |
            ConvertFrom-Yaml
        $quoted = Get-Content -Path (Join-Path $chapterPath '2.17.yaml') -Raw |
            ConvertFrom-Yaml
        $multiLine = Get-Content -Path (Join-Path $chapterPath '2.18.yaml') -Raw |
            ConvertFrom-Yaml

        $literal | Should -Match '\\//\|\|'
        $folded | Should -Be "Mark McGwire's year was crippled by a knee injury.`n"
        $quoted.unicode | Should -Be "Sosa did fine.$([char]0x263A)"
        $quoted.quoted | Should -Be " # Not a 'comment'."
        $multiLine.plain | Should -Be 'This unquoted scalar spans many lines.'
    }

    It 'constructs the Chapter 2 numeric examples with the core schema' {
        $integers = Get-Content -Path (Join-Path $chapterPath '2.19.yaml') -Raw |
            ConvertFrom-Yaml
        $floats = Get-Content -Path (Join-Path $chapterPath '2.20.yaml') -Raw |
            ConvertFrom-Yaml

        $integers.canonical | Should -Be 12345
        $integers.octal | Should -Be 12
        $integers.hexadecimal | Should -Be 12
        $floats.fixed | Should -Be 1230.15
        [double]::IsNegativeInfinity($floats.'negative infinity') | Should -BeTrue
        [double]::IsNaN($floats.'not a number') | Should -BeTrue
    }

    It 'keeps untagged timestamps as strings in Example 2.22' {
        $timestamps = Get-Content -Path (Join-Path $chapterPath '2.22.yaml') -Raw |
            ConvertFrom-Yaml

        $timestamps.canonical | Should -BeOfType [string]
        $timestamps.iso8601 | Should -BeOfType [string]
        $timestamps.spaced | Should -BeOfType [string]
        $timestamps.date | Should -BeOfType [string]
    }

    It 'handles explicit and application tags safely in Examples 2.23 and 2.24' {
        $tagged = Get-Content -Path (Join-Path $chapterPath '2.23.yaml') -Raw |
            ConvertFrom-Yaml
        $shapes = Get-Content -Path (Join-Path $chapterPath '2.24.yaml') -Raw |
            ConvertFrom-Yaml -NoEnumerate

        $tagged.'not-date' | Should -Be '2002-04-28'
        , $tagged.picture | Should -BeOfType [byte[]]
        $tagged.'application specific tag' | Should -BeOfType [string]
        [object]::ReferenceEquals($shapes[0].center, $shapes[1].start) | Should -BeTrue
        [object]::ReferenceEquals($shapes[0].center, $shapes[2].start) | Should -BeTrue
    }

    It 'constructs set and ordered-map tags from Examples 2.25 and 2.26' {
        $set = Get-Content -Path (Join-Path $chapterPath '2.25.yaml') -Raw |
            ConvertFrom-Yaml
        $orderedMap = Get-Content -Path (Join-Path $chapterPath '2.26.yaml') -Raw |
            ConvertFrom-Yaml

        $set | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        @($set.Keys) | Should -Be @('Mark McGwire', 'Sammy Sosa', 'Ken Griffey')
        $orderedMap | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        @($orderedMap.Keys) | Should -Be @('Mark McGwire', 'Sammy Sosa', 'Ken Griffey')
    }

    It 'preserves the invoice address alias identity in Example 2.27' {
        $invoice = Get-Content -Path (Join-Path $chapterPath '2.27.yaml') -Raw |
            ConvertFrom-Yaml

        [object]::ReferenceEquals($invoice.'bill-to', $invoice.'ship-to') | Should -BeTrue
        $invoice.product.Count | Should -Be 2
        $invoice.total | Should -Be 4443.52
    }
}

Describe 'Pinned yaml-test-suite reference cases' {
    BeforeAll {
        $suitePath = Join-Path $PSScriptRoot 'fixtures\yaml-test-suite'
    }

    It 'accepts valid reference case <Case>' -ForEach @(
        @{ Case = 'M5DY' }
        @{ Case = 'SBG9' }
        @{ Case = '6BFJ' }
        @{ Case = '565N' }
        @{ Case = 'EHF6' }
        @{ Case = 'VJP3-valid' }
    ) {
        $yaml = Get-Content -Path (Join-Path $suitePath "$Case.yaml") -Raw

        ($yaml | Test-Yaml) | Should -BeTrue
        { $yaml | ConvertFrom-Yaml -AsHashtable -NoEnumerate } | Should -Not -Throw
    }

    It 'rejects invalid reference case <Case>' -ForEach @(
        @{ Case = '2JQS' }
        @{ Case = 'SF5V' }
        @{ Case = 'H7TQ' }
        @{ Case = 'VJP3-invalid' }
    ) {
        $yaml = Get-Content -Path (Join-Path $suitePath "$Case.yaml") -Raw

        ($yaml | Test-Yaml) | Should -BeFalse
    }

    It 'constructs both binary spellings in case 565N identically' {
        $yaml = Get-Content -Path (Join-Path $suitePath '565N.yaml') -Raw
        $result = $yaml | ConvertFrom-Yaml

        [System.Linq.Enumerable]::SequenceEqual[byte](
            $result.canonical,
            $result.generic
        ) | Should -BeTrue
        , $result.canonical | Should -BeOfType [byte[]]
        , $result.generic | Should -BeOfType [byte[]]
        [System.Convert]::ToHexString(
            [System.Security.Cryptography.SHA256]::HashData($result.canonical)
        ) | Should -Be '0DD8F84D24840A21A56495526E5B227911D13389109C62194A64B6CCBF3B1400'
    }

    It 'projects the legacy ordered map in case J7PZ as an ordered dictionary' {
        $result = @'
--- !!omap
- Mark McGwire: 65
- Sammy Sosa: 63
- Ken Griffy: 58
'@ | ConvertFrom-Yaml

        $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        @($result.Keys) | Should -Be @('Mark McGwire', 'Sammy Sosa', 'Ken Griffy')
        @($result.Values) | Should -Be @(65, 63, 58)
    }
}
