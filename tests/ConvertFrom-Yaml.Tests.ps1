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

        It 'Treats .NET-specific special float tokens as strings (YAML 1.2.2)' {
            # YAML 1.2.2 core schema uses .inf/.nan (dot-prefix). Bare NaN/Infinity are plain strings.
            $yaml = @"
a: NaN
b: Infinity
c: -Infinity
d: +Infinity
e: nan
f: infinity
"@
            $result = $yaml | ConvertFrom-Yaml
            $result.a | Should -Be 'NaN'
            $result.a | Should -BeOfType [string]
            $result.b | Should -Be 'Infinity'
            $result.b | Should -BeOfType [string]
            $result.c | Should -Be '-Infinity'
            $result.c | Should -BeOfType [string]
            $result.d | Should -Be '+Infinity'
            $result.d | Should -BeOfType [string]
            $result.e | Should -Be 'nan'
            $result.e | Should -BeOfType [string]
            $result.f | Should -Be 'infinity'
            $result.f | Should -BeOfType [string]
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

        It 'Handles all supported double-quoted escapes (\r, \\, \", \0)' {
            $result = 'cr: "a\rb"' | ConvertFrom-Yaml
            $result.cr | Should -Be "a`rb"

            $result = 'bs: "a\\b"' | ConvertFrom-Yaml
            $result.bs | Should -Be 'a\b'

            $result = 'dq: "she said \"hi\""' | ConvertFrom-Yaml
            $result.dq | Should -Be 'she said "hi"'

            $result = 'nul: "a\0b"' | ConvertFrom-Yaml
            $result.nul | Should -Be "a$([char]0)b"
        }

        It 'Preserves single-quoted escape (double apostrophe)' {
            $result = "value: 'it''s a test'" | ConvertFrom-Yaml
            $result.value | Should -Be "it's a test"
        }

        It 'Parses a negative integer' {
            $result = 'value: -7' | ConvertFrom-Yaml
            $result.value | Should -Be -7
            $result.value | Should -BeOfType [int]
        }

        It 'Parses a large integer as [long]' {
            $result = 'value: 3000000000' | ConvertFrom-Yaml
            $result.value | Should -Be 3000000000
            $result.value | Should -BeOfType [long]
        }

        It 'Parses a negative floating-point value' {
            $result = 'value: -3.14' | ConvertFrom-Yaml
            $result.value | Should -Be -3.14
            $result.value | Should -BeOfType [double]
        }

        It 'Parses scientific notation as a double' {
            $result = 'value: 6.022e23' | ConvertFrom-Yaml
            $result.value | Should -Be 6.022e23
            $result.value | Should -BeOfType [double]
        }

        It 'Parses zero as an integer' {
            $result = 'value: 0' | ConvertFrom-Yaml
            $result.value | Should -Be 0
            $result.value | Should -BeOfType [int]
        }

        It 'Parses leading-zero integer as a number (YAML 1.2.2 core schema)' {
            $result = 'value: 01' | ConvertFrom-Yaml
            $result.value | Should -Be 1
            $result.value | Should -BeOfType [int]
        }

        It 'Parses leading-plus integer as a number (YAML 1.2.2 core schema)' {
            $result = 'value: +42' | ConvertFrom-Yaml
            $result.value | Should -Be 42
            $result.value | Should -BeOfType [int]
        }

        It 'Returns empty/whitespace-only input as null' {
            $result = '' | ConvertFrom-Yaml
            $result | Should -BeNullOrEmpty
            $result = '   ' | ConvertFrom-Yaml
            $result | Should -BeNullOrEmpty
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

        It 'Parses a mapping with null values' {
            $yaml = @'
present: value
empty:
tilde: ~
explicit: null
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.present | Should -Be 'value'
            $result.empty | Should -BeNullOrEmpty
            $result.tilde | Should -BeNullOrEmpty
            $result.explicit | Should -BeNullOrEmpty
        }

        It 'Parses a mapping with mixed value types' {
            $yaml = @'
str: hello
int: 10
float: 2.5
bool: true
nothing: null
list:
  - a
  - b
child:
  key: val
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.str | Should -Be 'hello'
            $result.str | Should -BeOfType [string]
            $result.int | Should -Be 10
            $result.float | Should -Be 2.5
            $result.bool | Should -BeTrue
            $result.nothing | Should -BeNullOrEmpty
            $result.list.Count | Should -Be 2
            $result.child.key | Should -Be 'val'
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

        It 'Parses nested sequences (sequence of sequences)' {
            $yaml = @'
matrix:
  -
    - 1
    - 2
  -
    - 3
    - 4
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.matrix.Count | Should -Be 2
            $result.matrix[0].Count | Should -Be 2
            $result.matrix[0][0] | Should -Be 1
            $result.matrix[1][1] | Should -Be 4
        }

        It 'Parses a sequence with null items' {
            $yaml = @'
- alpha
-
- bravo
'@
            $result = $yaml | ConvertFrom-Yaml -NoEnumerate
            $result.Count | Should -Be 3
            $result[0] | Should -Be 'alpha'
            $result[1] | Should -BeNullOrEmpty
            $result[2] | Should -Be 'bravo'
        }

        It 'Parses a sequence with mixed scalar types' {
            $yaml = @'
- hello
- 42
- true
- 3.14
- null
'@
            $result = $yaml | ConvertFrom-Yaml -NoEnumerate
            $result[0] | Should -Be 'hello'
            $result[0] | Should -BeOfType [string]
            $result[1] | Should -Be 42
            $result[1] | Should -BeOfType [int]
            $result[2] | Should -BeTrue
            $result[3] | Should -Be 3.14
            $result[3] | Should -BeOfType [double]
            $result[4] | Should -BeNullOrEmpty
        }

        It 'Parses indentless sequences as mapping values' {
            # YAML 1.2.2 allows sequences to start at the same indent as the parent mapping key.
            $yaml = @'
items:
- apple
- banana
other: val
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.items.Count | Should -Be 2
            $result.items[0] | Should -Be 'apple'
            $result.items[1] | Should -Be 'banana'
            $result.other | Should -Be 'val'
        }

        It 'Parses multiple indentless sequences in the same mapping' {
            $yaml = @'
list1:
- a
- b
list2:
- c
- d
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.list1.Count | Should -Be 2
            $result.list1[0] | Should -Be 'a'
            $result.list1[1] | Should -Be 'b'
            $result.list2.Count | Should -Be 2
            $result.list2[0] | Should -Be 'c'
            $result.list2[1] | Should -Be 'd'
        }

        It 'Parses indentless sequences of mappings' {
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

        It 'Parses sequence inline mappings with extra spaces after the dash' {
            # Valid YAML: the key may be indented further than "- " suggests.
            $yaml = @'
-   a: 1
    b: 2
-   x: alpha
    y: beta
'@
            $result = $yaml | ConvertFrom-Yaml -NoEnumerate
            $result.Count | Should -Be 2
            $result[0].a | Should -Be 1
            $result[0].b | Should -Be 2
            $result[1].x | Should -Be 'alpha'
            $result[1].y | Should -Be 'beta'
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

        It 'Without -NoEnumerate, unwraps a single-element top-level sequence' {
            $yaml = '- only'
            $result = $yaml | ConvertFrom-Yaml
            $result | Should -Be 'only'
            $result | Should -BeOfType [string]
        }
    }

    Context 'Pipeline input' {
        It 'Accepts multi-line pipeline strings (simulating Get-Content)' {
            $lines = @('name: Alice', 'age: 30')
            $result = $lines | ConvertFrom-Yaml
            $result.name | Should -Be 'Alice'
            $result.age | Should -Be 30
        }
    }

    Context 'Deeply nested structures' {
        It 'Parses 4 levels of nesting' {
            $yaml = @'
a:
  b:
    c:
      d: deep
'@
            $result = $yaml | ConvertFrom-Yaml
            $result.a.b.c.d | Should -Be 'deep'
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

        It 'Tolerates both --- and ... markers together' {
            $yaml = @'
---
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

        It 'Preserves # inside double-quoted strings' {
            $result = 'value: "has # inside"' | ConvertFrom-Yaml
            $result.value | Should -Be 'has # inside'
        }

        It 'Preserves # inside single-quoted strings' {
            $result = "value: 'has # inside'" | ConvertFrom-Yaml
            $result.value | Should -Be 'has # inside'
        }

        It 'Does not treat # without leading space as an inline comment' {
            $result = 'channel: news#general' | ConvertFrom-Yaml
            $result.channel | Should -Be 'news#general'
        }

        It 'Ignores blank lines' {
            $yaml = "name: Alice`n`nage: 30`n"
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

    Context 'Empty collection literals' {
        It 'Parses {} as an empty mapping (PSCustomObject by default)' {
            $result = 'data: {}' | ConvertFrom-Yaml
            $result.data | Should -BeOfType [PSCustomObject]
            @($result.data.PSObject.Properties).Count | Should -Be 0
        }

        It 'Parses {} as an empty OrderedDictionary with -AsHashtable' {
            $result = 'data: {}' | ConvertFrom-Yaml -AsHashtable
            $result['data'] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $result['data'].Count | Should -Be 0
        }

        It 'Parses [] as an empty array' {
            $result = 'items: []' | ConvertFrom-Yaml
            $result.items | Should -BeNullOrEmpty
            # Verify via round-trip that ConvertTo-Yaml emits []
            $yaml = [ordered]@{ items = @() } | ConvertTo-Yaml
            $yaml | Should -Match '\[\]'
        }

        It 'Parses sequence items {} and [] correctly' {
            $yaml = "- {}`n- []`n- hello"
            $result = $yaml | ConvertFrom-Yaml -NoEnumerate -AsHashtable
            $result[0] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $result[0].Count | Should -Be 0
            $result[1].Count | Should -Be 0
            $result[2] | Should -Be 'hello'
        }
    }

    Context 'Error handling' {
        It 'Throws on trailing unconsumed content' {
            # A mapping followed by a sequence at the same level is invalid at the root —
            # the parser should not silently discard the sequence.
            $yaml = @'
key: value
- orphan
'@
            { $yaml | ConvertFrom-Yaml } | Should -Throw '*unexpected content*'
        }
    }
}
