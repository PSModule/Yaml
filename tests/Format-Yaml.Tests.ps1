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

    function Get-TestYamlFailure {
        <#
            .SYNOPSIS
            Captures one expected terminating error for classification checks.
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
        throw 'The YAML operation unexpectedly succeeded.'
    }
}

Describe 'Format-Yaml' {
    Context 'Public contract' {
        It 'exposes the advanced string formatter contract' {
            $command = Get-Command -Name Format-Yaml
            $inputParameter = $command.Parameters['InputObject']
            $parameterAttribute = $inputParameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $allowEmptyString = $inputParameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.AllowEmptyStringAttribute] }
            $indentRange = $command.Parameters['Indent'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }

            $command.CmdletBinding | Should -BeTrue
            $inputParameter.ParameterType | Should -Be ([string[]])
            $parameterAttribute.Mandatory | Should -BeTrue
            $parameterAttribute.Position | Should -Be 0
            $parameterAttribute.ValueFromPipeline | Should -BeTrue
            $allowEmptyString | Should -Not -BeNullOrEmpty
            @($command.OutputType.Type) | Should -Contain ([string])
            $indentRange.MinRange | Should -Be 2
            $indentRange.MaxRange | Should -Be 9
        }
    }

    It 'emits exactly one string without CR or a final newline' {
        $result = @('one: 1', 'two: 2' | Format-Yaml)

        $result.Count | Should -Be 1
        $result[0] | Should -BeOfType [string]
        $result[0] | Should -Not -Match "`r"
        $result[0].EndsWith("`n", [System.StringComparison]::Ordinal) |
            Should -BeFalse
    }

    It 'returns one empty string for empty and comment-only streams' {
        $empty = @('' | Format-Yaml)
        $commentOnly = @("# heading`n# trailing" | Format-Yaml)

        $empty.Count | Should -Be 1
        $empty[0] | Should -BeExactly ''
        $commentOnly.Count | Should -Be 1
        $commentOnly[0] | Should -BeExactly ''
        ('---' | Format-Yaml) | Should -BeExactly '---'
    }
}

Context 'Deterministic normalization' {
    It 'removes comments and normalizes flow collections to block form' {
        $inputYaml = @'
# heading
root: { z: 1, a: "true", nested: [one, two] } # trailing
'@
        $expected = @'
---
"root":
  "z": 1
  "a": "true"
  "nested":
    - "one"
    - "two"
'@.Replace("`r`n", "`n").TrimEnd()

        ($inputYaml | Format-Yaml) | Should -BeExactly $expected
    }

    It 'uses the requested indentation' {
        $formatted = "outer:`n  inner:`n    value: one" | Format-Yaml -Indent 4

        $formatted | Should -Match '(?m)^    "inner":$'
        $formatted | Should -Match '(?m)^        "value": "one"$'
    }

    It 'joins pipeline records with LF into one stream' {
        $formatted = 'root:', '  child: value' | Format-Yaml

        $formatted | Should -BeExactly "---`n`"root`":`n  `"child`": `"value`""
    }

    It 'preserves empty documents and document order' {
        $inputYaml = "---`n...`n---`n# empty`n---`nvalue`n..."
        $formatted = $inputYaml | Format-Yaml
        $documents = @($formatted | ConvertFrom-Yaml)

        $formatted | Should -BeExactly "---`n---`n---`n`"value`""
        $documents.Count | Should -Be 3
        $documents[0] | Should -BeNullOrEmpty
        $documents[1] | Should -BeNullOrEmpty
        $documents[2] | Should -Be 'value'
    }

    It 'normalizes literal, folded, and chomping styles without changing content' {
        $inputYaml = @'
literal: |-
  first
  second
folded: >+
  alpha
  beta

'@
        $expectedValues = $inputYaml | ConvertFrom-Yaml -AsHashtable
        $formatted = $inputYaml | Format-Yaml
        $actualValues = $formatted | ConvertFrom-Yaml -AsHashtable

        $formatted | Should -Not -Match '(?m)^[|>][+-]?$'
        $formatted | Should -Match '\\n'
        $actualValues['literal'] | Should -BeExactly $expectedValues['literal']
        $actualValues['folded'] | Should -BeExactly $expectedValues['folded']
    }

    It 'quotes Unicode and control content safely' {
        $inputYaml = '"\0\a\b\t\n\r\e\x85\u263A\U0001F600"'
        $expected = $inputYaml | ConvertFrom-Yaml
        $formatted = $inputYaml | Format-Yaml

        ($formatted | ConvertFrom-Yaml) | Should -BeExactly $expected
        $formatted | Should -Match '\\0\\a\\b\\t\\n\\r\\e\\u0085'
        $formatted | Should -Not -Match "`r"
    }
}

Context 'Representation preservation' {
    It 'resolves tag directives and emits effective tags without directives' {
        $inputYaml = @'
%TAG !e! tag:example.com,2026:
---
!e!widget { value: !!str 42 }
'@
        $formatted = $inputYaml | Format-Yaml
        $before = Get-TestYamlRepresentationRoot -Yaml $inputYaml
        $after = Get-TestYamlRepresentationRoot -Yaml $formatted

        $formatted | Should -Not -Match '(?m)^%TAG'
        $formatted | Should -Match '!<tag:example\.com,2026:widget>'
        $formatted | Should -Match '!!str "42"'
        $after.Kind | Should -Be $before.Kind
        $after.Tag | Should -BeExactly $before.Tag
        $after.HasUnknownTag | Should -Be $before.HasUnknownTag
    }

    It 'preserves standard, local, global, escaped, and non-specific tags' -ForEach @(
        @{ Yaml = '!!binary SGVsbG8=' }
        @{ Yaml = '!local value' }
        @{ Yaml = '!<tag:example.test,2026:object> value' }
        @{ Yaml = '!<tag:example.test,2026:a%20b> value' }
        @{ Yaml = '! value' }
    ) {
        $formatted = $Yaml | Format-Yaml
        $before = Get-TestYamlRepresentationRoot -Yaml $Yaml
        $after = Get-TestYamlRepresentationRoot -Yaml $formatted

        $after.Kind | Should -Be $before.Kind
        $after.Tag | Should -BeExactly $before.Tag
        $after.HasUnknownTag | Should -Be $before.HasUnknownTag
        $after.Value | Should -BeExactly $before.Value
    }

    It 'preserves aliases and recursive graph identity with deterministic anchors' {
        $inputYaml = @'
root: &source
  self: *source
copy: *source
'@
        $formatted = $inputYaml | Format-Yaml
        $result = $formatted | ConvertFrom-Yaml -AsHashtable

        $formatted | Should -Match '&id001'
        @([regex]::Matches($formatted, '\*id001')).Count | Should -Be 2
        [object]::ReferenceEquals($result['root'], $result['copy']) |
            Should -BeTrue
        [object]::ReferenceEquals($result['root'], $result['root']['self']) |
            Should -BeTrue
    }

    It 'preserves complex keys and mapping order' {
        $inputYaml = @'
? [region, { port: 443 }]
: first
simple: second
'@
        $formatted = $inputYaml | Format-Yaml
        $result = $formatted | ConvertFrom-Yaml -AsHashtable
        $entry = $result.GetEnumerator() | Select-Object -First 1

        @($result.Values) | Should -Be @('first', 'second')
        , $entry.Key | Should -BeOfType [object[]]
        $entry.Key[0] | Should -Be 'region'
        $entry.Key[1] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $entry.Key[1]['port'] | Should -Be 443
    }

    It 'preserves explicit standard collection and scalar tags' -ForEach @(
        @{ Yaml = "!!set`n? one`n? two"; Kind = 'Mapping'; Tag = 'tag:yaml.org,2002:set' }
        @{ Yaml = "!!omap`n- one: 1`n- two: 2"; Kind = 'Sequence'; Tag = 'tag:yaml.org,2002:omap' }
        @{ Yaml = "!!pairs`n- one: 1`n- one: 2"; Kind = 'Sequence'; Tag = 'tag:yaml.org,2002:pairs' }
        @{ Yaml = '!!timestamp 2001-12-15T02:59:43.1Z'; Kind = 'Scalar'; Tag = 'tag:yaml.org,2002:timestamp' }
    ) {
        $formatted = $Yaml | Format-Yaml
        $node = Get-TestYamlRepresentationRoot -Yaml $formatted

        $node.Kind | Should -Be $Kind
        $node.Tag | Should -BeExactly $Tag
    }

    It 'keeps core-looking strings distinct from implicit core scalars' {
        $inputYaml = @'
quoted: "true"
tagged: !!str null
boolean: true
nullValue:
float: .nan
'@
        $formatted = $inputYaml | Format-Yaml
        $result = $formatted | ConvertFrom-Yaml -AsHashtable

        $result['quoted'] | Should -BeOfType [string]
        $result['quoted'] | Should -Be 'true'
        $result['tagged'] | Should -BeOfType [string]
        $result['tagged'] | Should -Be 'null'
        $result['boolean'] | Should -BeTrue
        $result['nullValue'] | Should -BeNullOrEmpty
        [double]::IsNaN($result['float']) | Should -BeTrue
    }

    It 'is byte-idempotent at the same options' -ForEach @(
        @{ Yaml = "# comment`n{ b: [2, 3], a: one }"; Indent = 2 }
        @{ Yaml = "&root [*root]"; Indent = 4 }
        @{ Yaml = "---`n`n---`n!local value"; Indent = 3 }
        @{ Yaml = "text: |+`n  one`n  two`n"; Indent = 2 }
    ) {
        $first = $Yaml | Format-Yaml -Indent $Indent
        $second = $first | Format-Yaml -Indent $Indent

        $second | Should -BeExactly $first
    }
}

Context 'Validation and parser limits' {
    It 'keeps exact effective tag-length boundaries idempotent' -ForEach @(
        @{
            Name    = 'local'
            Yaml    = '!abc value'
            TooLong = '!abcd value'
            Limit   = 4
        }
        @{
            Name    = 'verbatim'
            Yaml    = '!<a%20b> value'
            TooLong = '!<a%20bc> value'
            Limit   = 3
        }
        @{
            Name    = 'expanded handle'
            Yaml    = "%TAG !e! tag:x%2C`n---`n!e!a value"
            TooLong = "%TAG !e! tag:x%2C`n---`n!e!ab value"
            Limit   = 7
        }
    ) {
        $first = $Yaml | Format-Yaml -MaxTagLength $Limit
        $second = $first | Format-Yaml -MaxTagLength $Limit
        $failure = Get-TestYamlFailure {
            $TooLong | Format-Yaml -MaxTagLength $Limit
        }

        $second | Should -BeExactly $first
        $failure.Exception.Data['YamlErrorId'] |
            Should -BeExactly 'YamlTagLimitExceeded'
    }

    It 'keeps the default tag-length boundary idempotent' {
        $accepted = '!' + ('a' * 1023) + ' value'
        $rejected = '!' + ('a' * 1024) + ' value'

        $first = $accepted | Format-Yaml
        ($first | Format-Yaml) | Should -BeExactly $first
        $failure = Get-TestYamlFailure {
            $rejected | Format-Yaml
        }
        $failure.Exception.Data['YamlErrorId'] |
            Should -BeExactly 'YamlTagLimitExceeded'
    }

    It 'keeps cumulative effective tag budgets idempotent' {
        $yaml = "!abc one`n---`n!def two"
        $first = $yaml | Format-Yaml -MaxTagLength 4 -MaxTotalTagLength 8

        ($first | Format-Yaml -MaxTagLength 4 -MaxTotalTagLength 8) |
            Should -BeExactly $first
        $failure = Get-TestYamlFailure {
            $yaml | Format-Yaml -MaxTagLength 4 -MaxTotalTagLength 7
        }
        $failure.Exception.Data['YamlErrorId'] |
            Should -BeExactly 'YamlTagLimitExceeded'
    }

    It 'classifies every parser resource limit like ConvertFrom-Yaml' -ForEach @(
        @{ Name = 'depth'; Yaml = "a:`n  b:`n    c: value"; Parameters = @{ Depth = 2 } }
        @{ Name = 'nodes'; Yaml = '[one, two]'; Parameters = @{ MaxNodes = 2 } }
        @{ Name = 'aliases'; Yaml = "a: &a value`nb: *a"; Parameters = @{ MaxAliases = 0 } }
        @{ Name = 'scalar length'; Yaml = 'value: long'; Parameters = @{ MaxScalarLength = 4 } }
        @{ Name = 'tag length'; Yaml = '!long value'; Parameters = @{ MaxTagLength = 2 } }
        @{
            Name       = 'total tag length'
            Yaml       = "!a one`n---`n!b two"
            Parameters = @{ MaxTotalTagLength = 3 }
        }
        @{ Name = 'numeric length'; Yaml = '123'; Parameters = @{ MaxNumericLength = 2 } }
    ) {
        $parseFailure = Get-TestYamlFailure {
            $Yaml | ConvertFrom-Yaml @Parameters
        }
        $formatFailure = Get-TestYamlFailure {
            $Yaml | Format-Yaml @Parameters
        }

        $formatFailure.Exception.Data['YamlErrorId'] |
            Should -BeExactly $parseFailure.Exception.Data['YamlErrorId']
        $formatFailure.FullyQualifiedErrorId |
            Should -Be "$($parseFailure.Exception.Data['YamlErrorId']),Format-Yaml"
    }

    It 'classifies invalid YAML like ConvertFrom-Yaml' -ForEach @(
        @{ Name = 'malformed flow'; Yaml = '[one, two' }
        @{ Name = 'duplicate key'; Yaml = "key: one`nkey: two" }
        @{ Name = 'undefined alias'; Yaml = '*missing' }
        @{ Name = 'malformed tag'; Yaml = '!foo%GG value' }
    ) {
        $parseFailure = Get-TestYamlFailure { $Yaml | ConvertFrom-Yaml }
        $formatFailure = Get-TestYamlFailure { $Yaml | Format-Yaml }

        $formatFailure.Exception.Data['YamlErrorId'] |
            Should -BeExactly $parseFailure.Exception.Data['YamlErrorId']
        $formatFailure.FullyQualifiedErrorId |
            Should -Be "$($parseFailure.Exception.Data['YamlErrorId']),Format-Yaml"
    }

    It 'does not swallow unexpected runtime failures' {
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

        { 'name: Ada' | Format-Yaml } |
            Should -Throw -ExpectedMessage '*unexpected runtime failure*'
    }
}
