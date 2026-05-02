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

Describe 'ConvertFrom-Yaml' {

    Context 'Scalars' {
        It 'Parses a simple string value' {
            $result = 'name: World' | ConvertFrom-Yaml
            $result.name | Should -Be 'World'
        }

        It 'Parses an integer value' {
            $result = 'count: 42' | ConvertFrom-Yaml
            $result.count | Should -Be 42
            $result.count | Should -BeOfType [int]
        }

        It 'Parses a floating-point value' {
            $result = 'ratio: 1.5' | ConvertFrom-Yaml
            $result.ratio | Should -Be 1.5
            $result.ratio | Should -BeOfType [double]
        }

        It 'Parses boolean true variants' {
            $result = "a: true`nb: True`nc: yes" | ConvertFrom-Yaml
            $result.a | Should -BeTrue
            $result.b | Should -BeTrue
            $result.c | Should -BeTrue
        }

        It 'Parses boolean false variants' {
            $result = "a: false`nb: False`nc: no" | ConvertFrom-Yaml
            $result.a | Should -BeFalse
            $result.b | Should -BeFalse
            $result.c | Should -BeFalse
        }

        It 'Parses null values' {
            $result = "a: null`nb: ~`nc:" | ConvertFrom-Yaml
            $result.a | Should -BeNullOrEmpty
            $result.b | Should -BeNullOrEmpty
            $result.c | Should -BeNullOrEmpty
        }

        It 'Parses single-quoted strings preserving content' {
            $result = "value: 'true'" | ConvertFrom-Yaml
            $result.value | Should -Be 'true'
            $result.value | Should -BeOfType [string]
        }

        It 'Parses double-quoted strings preserving content' {
            $result = 'value: "42"' | ConvertFrom-Yaml
            $result.value | Should -Be '42'
            $result.value | Should -BeOfType [string]
        }

        It 'Handles double-quoted escape sequences' {
            $result = 'value: "line1\nline2\ttab"' | ConvertFrom-Yaml
            $result.value | Should -Be "line1`nline2`ttab"
        }
    }

    Context 'Mappings' {
        It 'Parses a flat mapping into a PSCustomObject by default' {
            $yaml = @"
name: Alice
age: 30
"@
            $result = $yaml | ConvertFrom-Yaml
            $result | Should -BeOfType [PSCustomObject]
            $result.name | Should -Be 'Alice'
            $result.age | Should -Be 30
        }

        It 'Parses nested mappings' {
            $yaml = @"
person:
  name: Alice
  address:
    city: Oslo
    country: Norway
"@
            $result = $yaml | ConvertFrom-Yaml
            $result.person.name | Should -Be 'Alice'
            $result.person.address.city | Should -Be 'Oslo'
            $result.person.address.country | Should -Be 'Norway'
        }

        It 'Preserves key insertion order' {
            $yaml = @"
zebra: 1
apple: 2
mango: 3
"@
            $result = $yaml | ConvertFrom-Yaml
            $names = $result.PSObject.Properties.Name
            $names[0] | Should -Be 'zebra'
            $names[1] | Should -Be 'apple'
            $names[2] | Should -Be 'mango'
        }
    }

    Context 'Sequences' {
        It 'Parses a sequence of scalars' {
            $yaml = @"
- one
- two
- three
"@
            $result = $yaml | ConvertFrom-Yaml -NoEnumerate
            $result.Count | Should -Be 3
            $result[0] | Should -Be 'one'
            $result[2] | Should -Be 'three'
        }

        It 'Parses a sequence under a key' {
            $yaml = @"
items:
  - apple
  - banana
  - cherry
"@
            $result = $yaml | ConvertFrom-Yaml
            $result.items.Count | Should -Be 3
            $result.items[1] | Should -Be 'banana'
        }

        It 'Parses a sequence of mappings' {
            $yaml = @"
people:
  - name: Alice
    age: 30
  - name: Bob
    age: 25
"@
            $result = $yaml | ConvertFrom-Yaml
            $result.people.Count | Should -Be 2
            $result.people[0].name | Should -Be 'Alice'
            $result.people[1].age | Should -Be 25
        }
    }

    Context '-AsHashtable' {
        It 'Returns an ordered dictionary instead of PSCustomObject' {
            $result = "a: 1`nb: 2" | ConvertFrom-Yaml -AsHashtable
            $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $result['a'] | Should -Be 1
            $result['b'] | Should -Be 2
        }

        It 'Returns nested structures as ordered dictionaries' {
            $yaml = @"
outer:
  inner:
    leaf: value
"@
            $result = $yaml | ConvertFrom-Yaml -AsHashtable
            $result['outer'] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $result['outer']['inner']['leaf'] | Should -Be 'value'
        }

        It 'Preserves key insertion order' {
            $result = "zebra: 1`napple: 2" | ConvertFrom-Yaml -AsHashtable
            @($result.Keys)[0] | Should -Be 'zebra'
            @($result.Keys)[1] | Should -Be 'apple'
        }
    }

    Context '-NoEnumerate' {
        It 'Returns a single-element top-level sequence as an array when -NoEnumerate is set' {
            $yaml = "- only"
            $result = $yaml | ConvertFrom-Yaml -NoEnumerate
            ,$result | Should -BeOfType [System.Object[]]
            $result.Count | Should -Be 1
        }
    }

    Context 'Frontmatter' {
        It 'Parses YAML between --- delimiters' {
            $content = @"
---
title: Hello
draft: false
---
# Markdown body here

Some content.
"@
            $result = $content | ConvertFrom-Yaml
            $result.title | Should -Be 'Hello'
            $result.draft | Should -BeFalse
        }

        It 'Parses content that is only frontmatter' {
            $content = @"
---
key: value
---
"@
            $result = $content | ConvertFrom-Yaml
            $result.key | Should -Be 'value'
        }
    }

    Context 'Comments and blank lines' {
        It 'Ignores full-line comments' {
            $yaml = @"
# this is a comment
name: Alice
# another comment
age: 30
"@
            $result = $yaml | ConvertFrom-Yaml
            $result.name | Should -Be 'Alice'
            $result.age | Should -Be 30
        }

        It 'Ignores inline comments after values' {
            $result = 'name: Alice  # the user' | ConvertFrom-Yaml
            $result.name | Should -Be 'Alice'
        }

        It 'Ignores blank lines' {
            $yaml = @"
name: Alice

age: 30

"@
            $result = $yaml | ConvertFrom-Yaml
            $result.name | Should -Be 'Alice'
            $result.age | Should -Be 30
        }
    }

    Context '-Depth' {
        It 'Throws when nesting exceeds -Depth' {
            $yaml = @"
a:
  b:
    c:
      d: value
"@
            { $yaml | ConvertFrom-Yaml -Depth 2 } | Should -Throw
        }

        It 'Allows nesting within -Depth' {
            $yaml = @"
a:
  b:
    c: value
"@
            $result = $yaml | ConvertFrom-Yaml -Depth 5
            $result.a.b.c | Should -Be 'value'
        }
    }

    Context 'Aliases' {
        It 'Has ConvertFrom-Yml as an alias' {
            (Get-Alias -Name ConvertFrom-Yml -ErrorAction SilentlyContinue).ResolvedCommand.Name |
                Should -Be 'ConvertFrom-Yaml'
        }
    }
}
