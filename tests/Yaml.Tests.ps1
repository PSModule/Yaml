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

Describe 'Yaml' {
    Describe 'ConvertFrom-Yaml' {
        Context 'ConvertFrom-Yaml - Basic scalar values' {
            It 'parses a simple YAML key-value pair' {
                $yaml = 'name: John Doe'
                $result = ConvertFrom-Yaml -Yaml $yaml
                $result | Should -BeOfType [PSCustomObject]
                $result.name | Should -Be 'John Doe'
            }
        }

        Context 'ConvertFrom-Yaml - Nested structure' {
            It 'parses a nested YAML structure' {
                $yaml = @'
person:
  name: John Doe
  age: 30
'@
                $result = ConvertFrom-Yaml -Yaml $yaml
                $result | Should -BeOfType [PSCustomObject]
                $result.person | Should -BeOfType [PSCustomObject]
                $result.person.name | Should -Be 'John Doe'
                $result.person.age | Should -Be 30
            }
        }

        Context 'ConvertFrom-Yaml - Arrays' {
            It 'parses a YAML list into a PowerShell array' {
                $yaml = @'
fruits:
  - Apple
  - Banana
  - Cherry
'@
                $result = ConvertFrom-Yaml -Yaml $yaml
                $result.fruits | Should -BeOfType [string[]]
                $result.fruits.Count | Should -Be 3
                $result.fruits[0] | Should -Be 'Apple'
            }
        }

        Context 'ConvertFrom-Yaml - Complex object' {
            It 'parses a complex YAML structure with mixed types' {
                $yaml = @'
company:
  name: TechCorp
  employees:
    - name: Alice
      age: 28
      skills: ["C#", "PowerShell"]
    - name: Bob
      age: 35
      skills:
        - Python
        - Go
'@
                $result = ConvertFrom-Yaml -Yaml $yaml
                $result.company | Should -BeOfType [PSCustomObject]
                $result.company.name | Should -Be 'TechCorp'
                $result.company.employees.Count | Should -Be 2
                $result.company.employees[0].name | Should -Be 'Alice'
                $result.company.employees[1].skills | Should -Contain 'Go'
            }
        }
    }

    Describe 'ConvertTo-Yaml' {
        Context 'ConvertTo-Yaml - Basic scalar values' {
            It 'converts a simple object to YAML' {
                $object = [PSCustomObject]@{ name = 'John Doe' }
                $yaml = ConvertTo-Yaml -Object $object
                $yaml | Should -Be 'name: \'John Doe\""
            }
        }

        Context 'ConvertTo-Yaml - Nested structure' {
            It 'converts a nested object to YAML' {
                $object = [PSCustomObject]@{ person = [PSCustomObject]@{ name = 'John Doe'; age = 30 } }
                $yaml = ConvertTo-Yaml -Object $object
                $yaml | Should -Match 'person:'
                $yaml | Should -Match '  name: \'John Doe\""
                $yaml | Should -Match '  age: 30'
            }
        }

        Context 'ConvertTo-Yaml - Arrays' {
            It 'converts an array to YAML' {
                $object = [PSCustomObject]@{ fruits = @('Apple', 'Banana', 'Cherry') }
                $yaml = ConvertTo-Yaml -Object $object
                $yaml | Should -Match 'fruits:'
                $yaml | Should -Match '  - \'Apple\""
                $yaml | Should -Match '  - \'Banana\""
                $yaml | Should -Match '  - \'Cherry\""
            }
        }

        Context 'ConvertTo-Yaml - YAML with comments' {
            It 'ignores comments in YAML while parsing' {
                $yaml = @"
# This is a comment
person:
  name: John Doe  # Inline comment
  age: 30
"@
                $result = ConvertFrom-Yaml -Yaml $yaml
                $result | Should -BeOfType [PSCustomObject]
                $result.person.name | Should -Be 'John Doe'
                $result.person.age | Should -Be 30
            }
        }
    }
}
