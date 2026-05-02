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

Describe 'ConvertTo-Yaml' {

    Context 'Scalars' {
        It 'Returns a string' {
            $yaml = @{ name = 'Alice' } | ConvertTo-Yaml
            $yaml | Should -BeOfType [string]
        }

        It 'Renders an integer without quotes' {
            $yaml = @{ count = 42 } | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'count: 42'
        }

        It 'Renders a double without quotes' {
            $yaml = @{ ratio = 1.5 } | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'ratio: 1.5'
        }

        It 'Renders booleans as lowercase true/false' {
            $yaml = ([ordered]@{ a = $true; b = $false }) | ConvertTo-Yaml
            $yaml | Should -Match 'a: true'
            $yaml | Should -Match 'b: false'
        }

        It 'Renders $null as the literal null' {
            $yaml = ([ordered]@{ a = $null }) | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'a: null'
        }

        It 'Quotes strings that look like booleans to preserve type' {
            $yaml = @{ value = 'true' } | ConvertTo-Yaml
            $yaml.Trim() | Should -Match "value:\s+(""true""|'true')"
        }

        It 'Quotes strings that look like numbers to preserve type' {
            $yaml = @{ value = '42' } | ConvertTo-Yaml
            $yaml.Trim() | Should -Match "value:\s+(""42""|'42')"
        }

        It 'Quotes strings that look like null to preserve type' {
            $yaml = @{ value = 'null' } | ConvertTo-Yaml
            $yaml.Trim() | Should -Match "value:\s+(""null""|'null')"
        }

        It 'Renders strings with special characters using double quotes and escapes' {
            $yaml = @{ value = "line1`nline2" } | ConvertTo-Yaml
            $yaml | Should -Match '"line1\\nline2"'
        }
    }

    Context 'Mappings' {
        It 'Renders a flat hashtable' {
            $yaml = ([ordered]@{ name = 'Alice'; age = 30 }) | ConvertTo-Yaml
            $lines = $yaml.TrimEnd("`r","`n") -split "`r?`n"
            $lines[0] | Should -Be 'name: Alice'
            $lines[1] | Should -Be 'age: 30'
        }

        It 'Renders nested mappings with 2-space indent by default' {
            $obj = [ordered]@{
                person = [ordered]@{
                    name = 'Alice'
                    address = [ordered]@{
                        city = 'Oslo'
                    }
                }
            }
            $yaml = $obj | ConvertTo-Yaml
            $yaml | Should -Match '(?m)^person:'
            $yaml | Should -Match '(?m)^  name: Alice'
            $yaml | Should -Match '(?m)^  address:'
            $yaml | Should -Match '(?m)^    city: Oslo'
        }

        It 'Renders a PSCustomObject' {
            $obj = [PSCustomObject]@{ name = 'Alice'; age = 30 }
            $yaml = $obj | ConvertTo-Yaml
            $yaml | Should -Match 'name: Alice'
            $yaml | Should -Match 'age: 30'
        }
    }

    Context 'Sequences' {
        It 'Renders a top-level array as a YAML sequence' {
            $yaml = ConvertTo-Yaml -InputObject @('one', 'two', 'three')
            $yaml | Should -Match '(?m)^- one'
            $yaml | Should -Match '(?m)^- two'
            $yaml | Should -Match '(?m)^- three'
        }

        It 'Renders an array under a key' {
            $obj = @{ items = @('a', 'b', 'c') }
            $yaml = $obj | ConvertTo-Yaml
            $yaml | Should -Match '(?m)^items:'
            $yaml | Should -Match '(?m)^  - a'
            $yaml | Should -Match '(?m)^  - b'
        }

        It 'Renders a sequence of mappings' {
            $obj = @{
                people = @(
                    [ordered]@{ name = 'Alice'; age = 30 }
                    [ordered]@{ name = 'Bob'; age = 25 }
                )
            }
            $yaml = $obj | ConvertTo-Yaml
            $yaml | Should -Match '(?m)^people:'
            $yaml | Should -Match '(?m)^  - name: Alice'
            $yaml | Should -Match '(?m)^    age: 30'
            $yaml | Should -Match '(?m)^  - name: Bob'
        }
    }

    Context '-AsArray' {
        It 'Wraps a single object in a top-level sequence' {
            $obj = [ordered]@{ name = 'Alice' }
            $yaml = ConvertTo-Yaml -InputObject $obj -AsArray
            $yaml | Should -Match '(?m)^- name: Alice'
        }
    }

    Context '-Indent' {
        It 'Uses 4 spaces when -Indent 4 is specified' {
            $obj = [ordered]@{
                outer = [ordered]@{
                    inner = 'value'
                }
            }
            $yaml = $obj | ConvertTo-Yaml -Indent 4
            $yaml | Should -Match '(?m)^outer:'
            $yaml | Should -Match '(?m)^    inner: value'
        }
    }

    Context '-EnumsAsStrings' {
        It 'Renders enum as string name when -EnumsAsStrings is set' {
            $obj = [ordered]@{ day = [System.DayOfWeek]::Monday }
            $yaml = $obj | ConvertTo-Yaml -EnumsAsStrings
            $yaml.Trim() | Should -Be 'day: Monday'
        }

        It 'Renders enum as integer value by default' {
            $obj = [ordered]@{ day = [System.DayOfWeek]::Monday }
            $yaml = $obj | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'day: 1'
        }
    }

    Context '-Depth' {
        It 'Truncates objects deeper than -Depth via ToString()' {
            $obj = [ordered]@{
                a = [ordered]@{
                    b = [ordered]@{
                        c = 'value'
                    }
                }
            }
            { $obj | ConvertTo-Yaml -Depth 1 -WarningAction SilentlyContinue } | Should -Not -Throw
        }

        It 'Renders within -Depth' {
            $obj = [ordered]@{
                a = [ordered]@{
                    b = 'value'
                }
            }
            $yaml = $obj | ConvertTo-Yaml -Depth 5
            $yaml | Should -Match 'b: value'
        }
    }

    Context 'Aliases' {
        It 'Has ConvertTo-Yml as an alias' {
            (Get-Alias -Name ConvertTo-Yml -ErrorAction SilentlyContinue).ResolvedCommand.Name |
                Should -Be 'ConvertTo-Yaml'
        }
    }
}

Describe 'Round-trip ConvertTo-Yaml | ConvertFrom-Yaml' {
    It 'Preserves a flat mapping' {
        $obj = [ordered]@{ name = 'Alice'; age = 30; active = $true }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['name'] | Should -Be 'Alice'
        $result['age'] | Should -Be 30
        $result['active'] | Should -BeTrue
    }

    It 'Preserves a nested mapping' {
        $obj = [ordered]@{
            person = [ordered]@{
                name = 'Alice'
                address = [ordered]@{
                    city = 'Oslo'
                    country = 'Norway'
                }
            }
        }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['person']['name'] | Should -Be 'Alice'
        $result['person']['address']['city'] | Should -Be 'Oslo'
        $result['person']['address']['country'] | Should -Be 'Norway'
    }

    It 'Preserves an array under a key' {
        $obj = [ordered]@{ items = @('a', 'b', 'c') }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['items'].Count | Should -Be 3
        $result['items'][0] | Should -Be 'a'
        $result['items'][2] | Should -Be 'c'
    }

    It 'Preserves a sequence of mappings' {
        $obj = [ordered]@{
            people = @(
                [ordered]@{ name = 'Alice'; age = 30 }
                [ordered]@{ name = 'Bob'; age = 25 }
            )
        }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['people'].Count | Should -Be 2
        $result['people'][0]['name'] | Should -Be 'Alice'
        $result['people'][1]['age'] | Should -Be 25
    }

    It 'Preserves quoted strings that look like other types' {
        $obj = [ordered]@{ a = 'true'; b = '42'; c = 'null' }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['a'] | Should -Be 'true'
        $result['a'] | Should -BeOfType [string]
        $result['b'] | Should -Be '42'
        $result['b'] | Should -BeOfType [string]
        $result['c'] | Should -Be 'null'
        $result['c'] | Should -BeOfType [string]
    }
}
