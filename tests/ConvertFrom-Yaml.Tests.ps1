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

        It 'Parses boolean true' {
            $result = 'a: true' | ConvertFrom-Yaml
            $result.a | Should -BeTrue
            $result.a | Should -BeOfType [bool]
        }

        It 'Parses boolean false' {
            $result = 'a: false' | ConvertFrom-Yaml
            $result.a | Should -BeFalse
            $result.a | Should -BeOfType [bool]
        }

        It 'Treats non-canonical boolean-like words as strings (YAML 1.2.2)' {
            # YAML 1.2.2 core schema only recognizes lowercase true/false. Everything else is a string.
            $yaml = @"
a: True
b: TRUE
c: yes
d: No
e: on
f: OFF
"@
            $result = $yaml | ConvertFrom-Yaml
            $result.a | Should -Be 'True'
            $result.a | Should -BeOfType [string]
            $result.b | Should -Be 'TRUE'
            $result.c | Should -Be 'yes'
            $result.d | Should -Be 'No'
            $result.e | Should -Be 'on'
            $result.f | Should -Be 'OFF'
        }

        It 'Parses null values' {
            $result = "a: null`nb: ~`nc:" | ConvertFrom-Yaml
            $result.a | Should -BeNullOrEmpty
            $result.b | Should -BeNullOrEmpty
            $result.c | Should -BeNullOrEmpty
        }

        It 'Treats non-canonical null-like words as strings (YAML 1.2.2)' {
            $result = "a: Null`nb: NULL" | ConvertFrom-Yaml
            $result.a | Should -Be 'Null'
            $result.a | Should -BeOfType [string]
            $result.b | Should -Be 'NULL'
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
            $yaml = @'
name: Alice
age: 30
'@
            $result = $yaml | ConvertFrom-Yaml
            $result | Should -BeOfType [PSCustomObject]
            $result.name | Should -Be 'Alice'
            $result.age | Should -Be 30
        }

        It 'Parses nested mappings' {
            $yaml = @'
person:
  name: Alice
  address:
    city: Oslo
    country: Norway
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.person.name | Should -Be 'Alice'
            $result.person.address.city | Should -Be 'Oslo'
            $result.person.address.country | Should -Be 'Norway'
        }

        It 'Preserves key insertion order' {
            $yaml = @'
zebra: 1
apple: 2
mango: 3
'@
            $result = $yaml | ConvertFrom-Yaml
            $names = $result.PSObject.Properties.Name
            $names[0] | Should -Be 'zebra'
            $names[1] | Should -Be 'apple'
            $names[2] | Should -Be 'mango'
        }

        It 'Preserves raw text of YAML-special keys without type resolution' {
            $yaml = @'
true: a
false: b
null: c
~: d
'@
            $result = $yaml | ConvertFrom-Yaml -AsHashtable
            $result.Keys | Should -Contain 'true'
            $result.Keys | Should -Contain 'false'
            $result.Keys | Should -Contain 'null'
            $result.Keys | Should -Contain '~'
            $result['true'] | Should -Be 'a'
            $result['false'] | Should -Be 'b'
            $result['null'] | Should -Be 'c'
            $result['~'] | Should -Be 'd'
        }

        It 'Handles quoted mapping keys with escapes' {
            $yaml = @'
"key\nwith": value1
'single''s': value2
'@
            $result = $yaml | ConvertFrom-Yaml -AsHashtable
            $result.Keys | Should -Contain "key`nwith"
            $result["key`nwith"] | Should -Be 'value1'
            $result.Keys | Should -Contain "single's"
            $result["single's"] | Should -Be 'value2'
        }

        It 'Parses keys that collide with built-in member names' {
            $yaml = @'
ToString: hello
GetType: world
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.PSObject.Properties['ToString'].Value | Should -Be 'hello'
            $result.PSObject.Properties['GetType'].Value | Should -Be 'world'
        }
    }

    Context 'Sequences' {
        It 'Parses a sequence of scalars' {
            $yaml = @'
- one
- two
- three
'@
            $result = $yaml | ConvertFrom-Yaml -NoEnumerate
            $result.Count | Should -Be 3
            $result[0] | Should -Be 'one'
            $result[2] | Should -Be 'three'
        }

        It 'Parses a sequence under a key' {
            $yaml = @'
items:
  - apple
  - banana
  - cherry
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.items.Count | Should -Be 3
            $result.items[1] | Should -Be 'banana'
        }

        It 'Parses a sequence of mappings' {
            $yaml = @'
people:
  - name: Alice
    age: 30
  - name: Bob
    age: 25
'@
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
            $yaml = @'
outer:
  inner:
    leaf: value
'@
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
            $yaml = '- only'
            $result = $yaml | ConvertFrom-Yaml -NoEnumerate
            , $result | Should -BeOfType [System.Object[]]
            $result.Count | Should -Be 1
        }
    }

    Context 'Document markers' {
        It 'Tolerates a leading --- document-start marker' {
            $yaml = @'
---
name: Alice
age: 30
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.name | Should -Be 'Alice'
            $result.age | Should -Be 30
        }

        It 'Tolerates a trailing ... document-end marker' {
            $yaml = @'
name: Alice
...
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.name | Should -Be 'Alice'
        }
    }

    Context 'Comments and blank lines' {
        It 'Ignores full-line comments' {
            $yaml = @'
# this is a comment
name: Alice
# another comment
age: 30
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.name | Should -Be 'Alice'
            $result.age | Should -Be 30
        }

        It 'Ignores inline comments after values' {
            $result = 'name: Alice  # the user' | ConvertFrom-Yaml
            $result.name | Should -Be 'Alice'
        }

        It 'Ignores blank lines' {
            $yaml = @'
name: Alice

age: 30

'@
            $result = $yaml | ConvertFrom-Yaml
            $result.name | Should -Be 'Alice'
            $result.age | Should -Be 30
        }
    }

    Context '-Depth' {
        It 'Throws when nesting exceeds -Depth' {
            $yaml = @'
a:
  b:
    c:
      d: value
'@
            { $yaml | ConvertFrom-Yaml -Depth 2 } | Should -Throw
        }

        It 'Allows nesting within -Depth' {
            $yaml = @'
a:
  b:
    c: value
'@
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
