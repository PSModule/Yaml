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

        It 'Renders strings with \r using double-quoted escapes' {
            $yaml = @{ value = "a`rb" } | ConvertTo-Yaml
            $yaml | Should -Match '"a\\rb"'
        }

        It 'Renders strings with backslash as plain text (no control characters)' {
            $yaml = @{ value = 'path\to\file' } | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'value: path\to\file'
        }

        It 'Renders an empty string with quotes' {
            $yaml = @{ value = '' } | ConvertTo-Yaml
            $yaml.Trim() | Should -Match "value:\s+''"
        }

        It 'Renders a negative integer without quotes' {
            $yaml = @{ value = -7 } | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'value: -7'
        }

        It 'Renders a [long] integer without quotes' {
            $yaml = @{ value = [long]3000000000 } | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'value: 3000000000'
        }

        It 'Renders a negative double without quotes' {
            $yaml = @{ value = -3.14 } | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'value: -3.14'
        }

        It 'Renders zero without quotes' {
            $yaml = @{ value = 0 } | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'value: 0'
        }

        It 'Quotes strings that look like tilde to preserve type' {
            $yaml = @{ value = '~' } | ConvertTo-Yaml
            $yaml.Trim() | Should -Match "value:\s+(""~""|'~')"
        }

        It 'Renders a DateTime as an ISO 8601 string' {
            $dt = [datetime]::new(2026, 5, 3, 12, 0, 0, [System.DateTimeKind]::Utc)
            $yaml = @{ value = $dt } | ConvertTo-Yaml
            $yaml | Should -Match '2026-05-03T12:00:00'
        }

        It 'Quotes strings containing a colon to prevent ambiguity' {
            $yaml = @{ value = 'http://example.com' } | ConvertTo-Yaml
            $yaml | Should -Match "(""http://example\.com""|'http://example\.com')"
        }

        It 'Quotes strings starting with special YAML characters' {
            $yaml = @{ value = '- not a list' } | ConvertTo-Yaml
            $yaml | Should -Match "(""- not a list""|'- not a list')"
        }
    }

    Context 'Mappings' {
        It 'Renders a flat hashtable' {
            $yaml = ([ordered]@{ name = 'Alice'; age = 30 }) | ConvertTo-Yaml
            $lines = $yaml.TrimEnd("`r", "`n") -split "`r?`n"
            $lines[0] | Should -Be 'name: Alice'
            $lines[1] | Should -Be 'age: 30'
        }

        It 'Renders nested mappings with 2-space indent by default' {
            $obj = [ordered]@{
                person = [ordered]@{
                    name    = 'Alice'
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

        It 'Renders a mapping with null values' {
            $yaml = ([ordered]@{ a = $null; b = 'ok' }) | ConvertTo-Yaml
            $yaml | Should -Match '(?m)^a: null'
            $yaml | Should -Match '(?m)^b: ok'
        }

        It 'Renders a mapping with mixed value types' {
            $obj = [ordered]@{
                str     = 'hello'
                int     = 10
                float   = 2.5
                bool    = $true
                nothing = $null
                list    = @('a', 'b')
                child   = [ordered]@{ key = 'val' }
            }
            $yaml = $obj | ConvertTo-Yaml
            $yaml | Should -Match '(?m)^str: hello'
            $yaml | Should -Match '(?m)^int: 10'
            $yaml | Should -Match '(?m)^float: 2\.5'
            $yaml | Should -Match '(?m)^bool: true'
            $yaml | Should -Match '(?m)^nothing: null'
            $yaml | Should -Match '(?m)^list:'
            $yaml | Should -Match '(?m)^  - a'
            $yaml | Should -Match '(?m)^child:'
            $yaml | Should -Match '(?m)^  key: val'
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

        It 'Renders nested sequences (array of arrays)' {
            $obj = [ordered]@{
                matrix = @(
                    , @(1, 2)
                    , @(3, 4)
                )
            }
            $yaml = $obj | ConvertTo-Yaml
            $yaml | Should -Match '(?m)^matrix:'
            $yaml | Should -Match '(?m)^  -'
            $yaml | Should -Match '(?m)^    - 1'
        }

        It 'Renders a sequence with null items' {
            $yaml = ConvertTo-Yaml -InputObject @('alpha', $null, 'bravo')
            $yaml | Should -Match '(?m)^- alpha'
            $yaml | Should -Match '(?m)^- null'
            $yaml | Should -Match '(?m)^- bravo'
        }

        It 'Renders a sequence with mixed scalar types' {
            $yaml = ConvertTo-Yaml -InputObject @('hello', 42, $true, 3.14, $null)
            $yaml | Should -Match '(?m)^- hello'
            $yaml | Should -Match '(?m)^- 42'
            $yaml | Should -Match '(?m)^- true'
            $yaml | Should -Match '(?m)^- 3\.14'
            $yaml | Should -Match '(?m)^- null'
        }
    }

    Context '-AsArray' {
        It 'Wraps a single object in a top-level sequence' {
            $obj = [ordered]@{ name = 'Alice' }
            $yaml = ConvertTo-Yaml -InputObject $obj -AsArray
            $yaml | Should -Match '(?m)^- name: Alice'
        }

        It 'Wraps multiple pipeline objects in a top-level sequence' {
            $yaml = @(
                [ordered]@{ name = 'Alice' }
                [ordered]@{ name = 'Bob' }
            ) | ConvertTo-Yaml -AsArray
            $yaml | Should -Match '(?m)^- name: Alice'
            $yaml | Should -Match '(?m)^- name: Bob'
        }
    }

    Context 'Pipeline input' {
        It 'Collects multiple pipeline objects into a sequence' {
            $yaml = 'Alice', 'Bob', 'Charlie' | ConvertTo-Yaml
            $yaml | Should -Match '(?m)^- Alice'
            $yaml | Should -Match '(?m)^- Bob'
            $yaml | Should -Match '(?m)^- Charlie'
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

        It 'Serializes enums with unsigned underlying type correctly' {
            # System.Security.AccessControl.FileSystemRights has UInt32 underlying type
            # and values that can exceed Int32.MaxValue
            $val = [System.Security.AccessControl.FileSystemRights]::FullControl
            $obj = [ordered]@{ rights = $val }
            $yaml = $obj | ConvertTo-Yaml
            $underlyingType = [System.Enum]::GetUnderlyingType($val.GetType())
            $numeric = [System.Convert]::ChangeType($val, $underlyingType)
            $expected = ([System.IConvertible]$numeric).ToString([cultureinfo]::InvariantCulture)
            $yaml.Trim() | Should -Be "rights: $expected"
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

        It 'Indents depth-exceeded values correctly under a mapping key' {
            $obj = [ordered]@{
                a = [ordered]@{
                    b = [ordered]@{
                        c = 'value'
                    }
                }
            }
            $yaml = $obj | ConvertTo-Yaml -Depth 1 -WarningAction SilentlyContinue
            $lines = $yaml.TrimEnd("`r", "`n") -split "`r?`n"
            # The depth-exceeded line should be indented under 'b:'
            $bLine = $lines | Where-Object { $_ -match '^\s+b:' }
            $bLine | Should -Not -BeNullOrEmpty
            $depthLine = $lines[([array]::IndexOf($lines, $bLine) + 1)]
            $depthLine | Should -Match '^\s{4}'
        }

        It 'Truncates deeply nested sequences beyond -Depth' {
            $inner = , ('innermost')
            $middle = , $inner
            $outer = , $middle
            $yaml = ConvertTo-Yaml -InputObject $outer -Depth 1 -WarningAction SilentlyContinue
            $yaml | Should -Not -BeNullOrEmpty
            $yaml | Should -Not -Match 'innermost'
        }

        It 'Truncates sequences under mapping keys beyond -Depth' {
            $obj = [ordered]@{
                a = [ordered]@{
                    b = @(1, 2, 3)
                }
            }
            $yaml = $obj | ConvertTo-Yaml -Depth 1 -WarningAction SilentlyContinue
            $yaml | Should -Not -BeNullOrEmpty
            $yaml | Should -Not -Match '- 1'
        }
    }

    Context 'Empty collections' {
        It 'Renders an empty hashtable as {}' {
            $yaml = [ordered]@{} | ConvertTo-Yaml
            $yaml.Trim() | Should -Be '{}'
        }

        It 'Renders an empty array as []' {
            $yaml = ConvertTo-Yaml -InputObject @()
            $yaml.Trim() | Should -Be '[]'
        }

        It 'Renders a nested empty mapping inline' {
            $obj = [ordered]@{ key = [ordered]@{} }
            $yaml = $obj | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'key: {}'
        }

        It 'Renders a nested empty array inline' {
            $obj = [ordered]@{ key = @() }
            $yaml = $obj | ConvertTo-Yaml
            $yaml.Trim() | Should -Be 'key: []'
        }

        It 'Renders an empty mapping value in a sequence-of-mappings inline' {
            $obj = @(
                [ordered]@{ name = 'Alice'; data = [ordered]@{} }
            )
            $yaml = ConvertTo-Yaml -InputObject $obj
            $yaml | Should -Match 'data: \{\}'
        }

        It 'Renders an empty array value in a sequence-of-mappings inline' {
            $obj = @(
                [ordered]@{ name = 'Alice'; items = @() }
            )
            $yaml = ConvertTo-Yaml -InputObject $obj
            $yaml | Should -Match 'items: \[\]'
        }

        It 'Renders an empty sequence item in a sequence as - []' {
            $obj = @( @(), @('a') )
            $yaml = ConvertTo-Yaml -InputObject $obj
            $yaml | Should -Match '(?m)^- \[\]'
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
                name    = 'Alice'
                address = [ordered]@{
                    city    = 'Oslo'
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

    It 'Preserves an empty mapping under a key' {
        $obj = [ordered]@{ data = [ordered]@{} }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['data'] | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
        $result['data'].Count | Should -Be 0
    }

    It 'Preserves an empty array under a key' {
        $obj = [ordered]@{ items = @() }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['items'].Count | Should -Be 0
    }

    It 'Preserves numeric types (int, long, double, negative)' {
        $obj = [ordered]@{
            int    = 42
            long   = [long]3000000000
            double = 3.14
            neg    = -7
            zero   = 0
        }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['int'] | Should -Be 42
        $result['int'] | Should -BeOfType [int]
        $result['long'] | Should -Be 3000000000
        $result['long'] | Should -BeOfType [long]
        $result['double'] | Should -Be 3.14
        $result['double'] | Should -BeOfType [double]
        $result['neg'] | Should -Be -7
        $result['zero'] | Should -Be 0
    }

    It 'Round-trips booleans and null through unquoted YAML literals' {
        $obj = [ordered]@{ yes = $true; no = $false; nothing = $null }
        $yaml = $obj | ConvertTo-Yaml

        # Intermediate YAML must use unquoted canonical literals
        $yaml | Should -Match '(?m)^yes: true\r?$'
        $yaml | Should -Match '(?m)^no: false\r?$'
        $yaml | Should -Match '(?m)^nothing: null\r?$'

        # Round-trip back to PowerShell must restore native types
        $result = $yaml | ConvertFrom-Yaml -AsHashtable
        $result['yes'] | Should -BeTrue
        $result['yes'] | Should -BeOfType [bool]
        $result['no'] | Should -BeFalse
        $result['no'] | Should -BeOfType [bool]
        $result['nothing'] | Should -BeNullOrEmpty
    }

    It 'Preserves strings with special characters' {
        $obj = [ordered]@{
            newline   = "line1`nline2"
            tab       = "col1`tcol2"
            backslash = 'a\b'
        }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['newline'] | Should -Be "line1`nline2"
        $result['tab'] | Should -Be "col1`tcol2"
        $result['backslash'] | Should -Be 'a\b'
    }

    It 'Preserves tilde as a string when quoted' {
        $obj = [ordered]@{ value = '~' }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['value'] | Should -Be '~'
        $result['value'] | Should -BeOfType [string]
    }

    It 'Preserves a deeply nested structure' {
        $obj = [ordered]@{
            a = [ordered]@{
                b = [ordered]@{
                    c = [ordered]@{
                        d = 'deep'
                    }
                }
            }
        }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['a']['b']['c']['d'] | Should -Be 'deep'
    }

    It 'Preserves a mixed structure (mappings, sequences, nested)' {
        $obj = [ordered]@{
            name    = 'project'
            version = 1
            tags    = @('alpha', 'beta')
            config  = [ordered]@{
                debug   = $true
                timeout = 30
            }
            servers = @(
                [ordered]@{ host = 'a.example.com'; port = 80 }
                [ordered]@{ host = 'b.example.com'; port = 443 }
            )
        }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['name'] | Should -Be 'project'
        $result['version'] | Should -Be 1
        $result['tags'].Count | Should -Be 2
        $result['tags'][0] | Should -Be 'alpha'
        $result['config']['debug'] | Should -BeTrue
        $result['config']['timeout'] | Should -Be 30
        $result['servers'].Count | Should -Be 2
        $result['servers'][0]['host'] | Should -Be 'a.example.com'
        $result['servers'][1]['port'] | Should -Be 443
    }

    It 'Preserves an empty string' {
        $obj = [ordered]@{ value = '' }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['value'] | Should -Be ''
        $result['value'] | Should -BeOfType [string]
    }

    It 'Round-trips control characters via \xHH escapes' {
        # Format-YamlDoubleQuoted emits \xHH for control chars (e.g. NUL, BEL).
        # Expand-YamlDoubleQuoted must parse them back correctly.
        $nul = [string][char]0
        $bel = [string][char]7
        $obj = [ordered]@{ nul = $nul; bel = $bel }
        $result = $obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
        $result['nul'] | Should -Be $nul
        $result['bel'] | Should -Be $bel
    }
}
