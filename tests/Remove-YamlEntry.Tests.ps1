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

    function Get-RemoveYamlFailure {
        <#
            .SYNOPSIS
            Captures one expected terminating Remove-YamlEntry error.
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
        throw 'The YAML removal unexpectedly succeeded.'
    }

    function Invoke-RemoveYamlAmbiguityProbe {
        <#
            .SYNOPSIS
            Creates an otherwise unreachable ambiguous representation mapping.
        #>
        $implementation = {
            $document = (Read-YamlStreamCore -Yaml 'key: value' -Depth 100 -MaxNodes 100 `
                    -MaxAliases 100 -MaxScalarLength 1048576 -MaxTagLength 1024 `
                    -MaxTotalTagLength 65536 -MaxNumericLength 4096).Value[0]
            $document.Entries.Add([pscustomobject]@{
                    Key   = $document.Entries[0].Key
                    Value = $document.Entries[0].Value
                })
            $state = [pscustomobject]@{ Count = 0L; MaxNodes = 100 }
            $tokens = (ConvertFrom-YamlJsonPointer -Pointer '/key' -State $state).Value
            Resolve-YamlRemovalTarget -Document $document -DocumentIndex 0 `
                -Pointer '/key' -Tokens $tokens -State $state
        }

        $loadedModule = Get-Module -Name Yaml | Select-Object -First 1
        if ($null -eq $loadedModule) {
            return & $implementation
        }
        return & $loadedModule $implementation
    }

    function Measure-RemoveYamlWork {
        <#
            .SYNOPSIS
            Captures the deterministic removal work count.
        #>
        param (
            [Parameter(Mandatory)]
            [string] $Yaml,

            [Parameter(Mandatory)]
            [AllowEmptyString()]
            [string[]] $Path,

            [Parameter()]
            [hashtable] $Parameters = @{}
        )

        $records = @(
            Remove-YamlEntry -InputObject $Yaml -Path $Path @Parameters -Debug 5>&1
        )
        $debugText = $records |
            ForEach-Object ToString |
            Where-Object { $_ -like '*Remove-YamlEntry work operations:*' } |
            Select-Object -Last 1
        if ($null -eq $debugText -or
            $debugText -notmatch 'Remove-YamlEntry work operations: (?<WorkCount>\d+)') {
            throw 'Remove-YamlEntry did not report its deterministic work count.'
        }
        $output = $records |
            Where-Object { $_ -isnot [System.Management.Automation.DebugRecord] } |
            Select-Object -First 1

        [pscustomobject]@{
            Output = [string] $output
            Count  = [long] $Matches.WorkCount
        }
    }
}

Describe 'Remove-YamlEntry' {
    Context 'Public contract' {
        It 'exposes one advanced string transformation contract' {
            $command = Get-Command -Name Remove-YamlEntry
            $inputParameter = $command.Parameters['InputObject']
            $inputAttribute = $inputParameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $inputAllowsEmpty = $inputParameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.AllowEmptyStringAttribute] }
            $pathParameter = $command.Parameters['Path']
            $pathAttribute = $pathParameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] }
            $pathAllowsEmpty = $pathParameter.Attributes |
                Where-Object { $_ -is [System.Management.Automation.AllowEmptyStringAttribute] }
            $documentIndexRange = $command.Parameters['DocumentIndex'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $indentRange = $command.Parameters['Indent'].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }
            $help = Get-Help -Name Remove-YamlEntry -Full

            $command.CmdletBinding | Should -BeTrue
            $command.DefaultParameterSet | Should -BeExactly 'Document'
            @($command.ParameterSets.Name | Sort-Object) |
                Should -Be @('AllDocuments', 'Document')
            $command.Parameters.ContainsKey('WhatIf') | Should -BeFalse
            $command.Parameters.ContainsKey('Confirm') | Should -BeFalse
            $inputParameter.ParameterType | Should -Be ([string[]])
            $inputAttribute.Mandatory | Should -BeTrue
            $inputAttribute.Position | Should -Be 0
            $inputAttribute.ValueFromPipeline | Should -BeTrue
            $inputAllowsEmpty | Should -Not -BeNullOrEmpty
            $pathParameter.ParameterType | Should -Be ([string[]])
            $pathAttribute.Mandatory | Should -BeTrue
            $pathAttribute.Position | Should -Be 1
            $pathAllowsEmpty | Should -Not -BeNullOrEmpty
            $documentIndexRange.MinRange | Should -Be 0
            $documentIndexRange.MaxRange | Should -Be 2147483647
            $indentRange.MinRange | Should -Be 2
            $indentRange.MaxRange | Should -Be 9
            @($command.OutputType.Type) | Should -Contain ([string])
            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description.Text | Should -Match 'JSON Pointer'
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 3
        }

        It 'separates one-document and all-document selection' {
            $command = Get-Command -Name Remove-YamlEntry
            $documentSet = $command.ParameterSets |
                Where-Object Name -EQ 'Document'
            $allSet = $command.ParameterSets |
                Where-Object Name -EQ 'AllDocuments'

            ($documentSet.Parameters | Where-Object Name -EQ 'DocumentIndex').IsMandatory |
                Should -BeFalse
            @($documentSet.Parameters.Name) | Should -Not -Contain 'AllDocuments'
            ($allSet.Parameters | Where-Object Name -EQ 'AllDocuments').IsMandatory |
                Should -BeTrue
            @($allSet.Parameters.Name) | Should -Not -Contain 'DocumentIndex'
        }

        It 'mirrors every parser safety range' -ForEach @(
            @{ Name = 'Depth'; Minimum = 1; Maximum = 128 }
            @{ Name = 'MaxNodes'; Minimum = 1; Maximum = 2147483647 }
            @{ Name = 'MaxAliases'; Minimum = 0; Maximum = 2147483647 }
            @{ Name = 'MaxScalarLength'; Minimum = 1; Maximum = 2147483647 }
            @{ Name = 'MaxTagLength'; Minimum = 1; Maximum = 1048576 }
            @{ Name = 'MaxTotalTagLength'; Minimum = 1; Maximum = 2147483647 }
            @{ Name = 'MaxNumericLength'; Minimum = 1; Maximum = 1048576 }
        ) {
            $range = (Get-Command Remove-YamlEntry).Parameters[$Name].Attributes |
                Where-Object { $_ -is [System.Management.Automation.ValidateRangeAttribute] }

            $range.MinRange | Should -Be $Minimum
            $range.MaxRange | Should -Be $Maximum
        }

        It 'aggregates direct and pipeline string records with LF' {
            $records = @('root:', '  keep: true', '  drop: false')
            $expected = "root:`n  keep: true" | Format-Yaml

            (Remove-YamlEntry -InputObject $records -Path '/root/drop') |
                Should -BeExactly $expected
            ($records | Remove-YamlEntry -Path '/root/drop') |
                Should -BeExactly $expected
        }

        It 'emits exactly one LF-only string without a final newline' {
            $result = @(
                Remove-YamlEntry -InputObject "keep: true`r`ndrop: false`r`n" -Path '/drop'
            )

            $result.Count | Should -Be 1
            $result[0] | Should -BeOfType [string]
            $result[0] | Should -Not -Match "`r"
            $result[0].EndsWith("`n", [System.StringComparison]::Ordinal) |
                Should -BeFalse
        }
    }

    Context 'JSON Pointer and mapping keys' {
        It 'addresses empty, numeric-looking, escaped, Unicode, and case-sensitive keys' {
            $unicodeKey = [char] 0x00C5
            $yaml = @"
"": empty
"01": numeric-looking
"a/b": slash
"a~b": tilde
"~1": escaped-twice
"$unicodeKey": unicode
Name: upper
name: lower
keep: true
"@
            $actual = Remove-YamlEntry $yaml @(
                '/'
                '/01'
                '/a~1b'
                '/a~0b'
                '/~01'
                "/$unicodeKey"
                '/Name'
            )

            $actual | Should -BeExactly ("name: lower`nkeep: true" | Format-Yaml)
        }

        It 'matches mapping key code points ordinally' {
            $composed = [string] [char] 0x00E9
            $decomposed = 'e' + [char] 0x0301
            $yaml = '"' + $decomposed + '": value' + "`nkeep: true"

            Remove-YamlEntry $yaml ('/' + $composed) -IgnoreMissing |
                Should -BeExactly ($yaml | Format-Yaml)

            $result = Remove-YamlEntry $yaml ('/' + $decomposed) |
                ConvertFrom-Yaml -AsHashtable
            $result.Contains($decomposed) | Should -BeFalse
            $result['keep'] | Should -BeTrue
        }

        It 'does not treat a linguistically equal unknown tag as a string tag' {
            $yaml = "!<tag:yaml.org,2002:st%C2%ADr> key: tagged`nkeep: true"

            Remove-YamlEntry $yaml '/key' -IgnoreMissing |
                Should -BeExactly ($yaml | Format-Yaml)
        }

        It 'treats explicit string keys as strings and plain numeric keys as numbers' {
            $yaml = @'
1: numeric
!!str 1: string
'@

            (Remove-YamlEntry $yaml '/1') |
                Should -BeExactly ('1: numeric' | Format-Yaml)
        }

        It 'rejects pointers that do not start with slash' {
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry 'key: value' 'key'
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalInvalidPointer'
            $failure.FullyQualifiedErrorId |
                Should -Be 'YamlRemovalInvalidPointer,Remove-YamlEntry'
        }

        It 'rejects every malformed tilde escape' -ForEach @(
            @{ Pointer = '/key~' }
            @{ Pointer = '/key~2' }
            @{ Pointer = '/key~x' }
            @{ Pointer = '/key~~0' }
        ) {
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry 'key: value' $Pointer -IgnoreMissing
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalInvalidPointerEscape'
        }

        It 'does not guess among ambiguous matching string keys' {
            $failure = Get-RemoveYamlFailure {
                Invoke-RemoveYamlAmbiguityProbe
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalAmbiguousTarget'
        }

        It 'preserves complex, non-string, and unknown-tagged keys as unaddressable' {
            $yaml = @'
? [complex]
: sequence-key
2: numeric-key
!key tagged: tagged-key
keep: true
'@
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry $yaml '/tagged'
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalPathNotFound'
            $failure.Exception.Message | Should -Match 'cannot be addressed'
            (Remove-YamlEntry $yaml '/tagged' -IgnoreMissing) |
                Should -BeExactly ($yaml | Format-Yaml)
        }
    }

    Context 'Sequence and nested traversal' {
        It 'removes nested mapping and sequence entries' {
            $yaml = @'
root:
  items:
    - keep: zero
      drop: zero
    - keep: one
      drop: one
'@
            $expected = @'
root:
  items:
    - keep: zero
      drop: zero
    - keep: one
'@ | Format-Yaml

            (Remove-YamlEntry $yaml '/root/items/1/drop') |
                Should -BeExactly $expected
        }

        It 'accepts only canonical non-negative decimal sequence indexes' -ForEach @(
            @{ Token = '-' }
            @{ Token = '+1' }
            @{ Token = '-1' }
            @{ Token = '01' }
            @{ Token = '1.0' }
            @{ Token = '2147483648' }
        ) {
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry '[zero, one]' "/$Token" -IgnoreMissing
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalInvalidSequenceIndex'
        }

        It 'treats out-of-range sequence indexes as missing' {
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry '[zero, one]' '/2'
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalPathNotFound'
            (Remove-YamlEntry '[zero, one]' '/2' -IgnoreMissing) |
                Should -BeExactly ('[zero, one]' | Format-Yaml)
        }

        It 'treats traversal through a scalar as missing' {
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry 'root: scalar' '/root/child'
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalPathNotFound'
        }
    }

    Context 'Missing targets and transactions' {
        It 'terminates before emitting changes when any path is missing' {
            $output = @()
            try {
                $output = @(
                    Remove-YamlEntry 'first: 1' @('/first', '/missing')
                )
                throw 'The YAML removal unexpectedly succeeded.'
            } catch {
                $failure = $_
            }

            $output.Count | Should -Be 0
            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalPathNotFound'
        }

        It 'skips only unresolved targets with IgnoreMissing' {
            $actual = Remove-YamlEntry 'first: 1' @('/missing', '/first') -IgnoreMissing

            $actual | Should -BeExactly ('{}' | Format-Yaml)
        }

        It 'is idempotent when repeated with IgnoreMissing' {
            $first = Remove-YamlEntry 'keep: true' '/drop' -IgnoreMissing
            $second = Remove-YamlEntry $first '/drop' -IgnoreMissing

            $second | Should -BeExactly $first
        }
    }

    Context 'Document selection and root removal' {
        It 'uses zero-based document index zero by default' {
            $yaml = "---`ndrop: first`nkeep: one`n---`ndrop: second`nkeep: two"
            $documents = @(
                Remove-YamlEntry $yaml '/drop' |
                    ConvertFrom-Yaml -AsHashtable
            )

            $documents.Count | Should -Be 2
            $documents[0].Contains('drop') | Should -BeFalse
            $documents[1]['drop'] | Should -Be 'second'
        }

        It 'selects one explicit document index' {
            $yaml = "---`ndrop: first`n---`ndrop: second"
            $documents = @(
                Remove-YamlEntry $yaml '/drop' -DocumentIndex 1 |
                    ConvertFrom-Yaml -AsHashtable
            )

            $documents[0]['drop'] | Should -Be 'first'
            $documents[1].Contains('drop') | Should -BeFalse
        }

        It 'rejects an unavailable document index even with IgnoreMissing' {
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry 'key: value' '/key' -DocumentIndex 1 -IgnoreMissing
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalDocumentIndexOutOfRange'
        }

        It 'requires each path in each document unless IgnoreMissing is used' {
            $yaml = "---`ndrop: first`n---`nkeep: second"
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry $yaml '/drop' -AllDocuments
            }
            $documents = @(
                Remove-YamlEntry $yaml '/drop' -AllDocuments -IgnoreMissing |
                    ConvertFrom-Yaml -AsHashtable
            )

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalPathNotFound'
            $documents[0].Contains('drop') | Should -BeFalse
            $documents[1]['keep'] | Should -Be 'second'
        }

        It 'removes one selected document with an empty pointer' {
            $yaml = "---`nfirst: true`n---`nsecond: true`n---`nthird: true"
            $documents = @(
                Remove-YamlEntry $yaml '' -DocumentIndex 1 |
                    ConvertFrom-Yaml -AsHashtable
            )

            $documents.Count | Should -Be 2
            $documents[0]['first'] | Should -BeTrue
            $documents[1]['third'] | Should -BeTrue
        }

        It 'removes all documents with AllDocuments and an empty pointer' {
            $result = @(
                Remove-YamlEntry "---`nfirst: true`n---`nsecond: true" '' -AllDocuments
            )

            $result.Count | Should -Be 1
            $result[0] | Should -BeExactly ''
        }
    }

    Context 'Multiple-path ordering and coalescing' {
        It 'coalesces duplicate targets' {
            (Remove-YamlEntry 'keep: true' @('/keep', '/keep', '/keep')) |
                Should -BeExactly ('{}' | Format-Yaml)
        }

        It 'lets an ancestor removal subsume its descendant' {
            $yaml = "root:`n  child: value`nkeep: true"

            (Remove-YamlEntry $yaml @('/root/child', '/root')) |
                Should -BeExactly ('keep: true' | Format-Yaml)
        }

        It 'removes original sequence indexes in descending order' {
            (Remove-YamlEntry '[zero, one, two, three, four]' @('/1', '/3')) |
                Should -BeExactly ('[zero, two, four]' | Format-Yaml)
        }

        It 'preserves mapping order among surviving entries' {
            $yaml = "first: 1`nsecond: 2`nthird: 3`nfourth: 4"
            $expected = "first: 1`nthird: 3" | Format-Yaml

            (Remove-YamlEntry $yaml @('/fourth', '/second')) |
                Should -BeExactly $expected
        }

        It 'coalesces one shared target reached through direct and alias paths' {
            $yaml = @'
root: &shared
  drop: true
  keep: true
copy: *shared
'@
            $result = Remove-YamlEntry $yaml @('/root/drop', '/copy/drop') |
                ConvertFrom-Yaml -AsHashtable

            $result['root'].Contains('drop') | Should -BeFalse
            $result['copy'].Contains('drop') | Should -BeFalse
            [object]::ReferenceEquals($result['root'], $result['copy']) |
                Should -BeTrue
        }

        It 'keeps an independently requested shared mutation when one alias ancestor is removed' {
            $yaml = @'
root: &shared
  drop: true
  keep: true
copy: *shared
'@
            $result = Remove-YamlEntry $yaml @('/copy', '/root/drop') |
                ConvertFrom-Yaml -AsHashtable

            $result.Contains('copy') | Should -BeFalse
            $result['root'].Contains('drop') | Should -BeFalse
        }

        It 'orders shared mapping removals by original index across pointer depths' {
            $yaml = @'
a: &shared
  x: 1
  y: 2
b:
  c: *shared
'@
            $result = Remove-YamlEntry $yaml @('/a/y', '/b/c/x') |
                ConvertFrom-Yaml -AsHashtable

            $result['a'].Count | Should -Be 0
            [object]::ReferenceEquals($result['a'], $result['b']['c']) |
                Should -BeTrue
        }

        It 'orders shared sequence removals by original index across pointer depths' {
            $yaml = "a: &shared [zero, one, two]`nb:`n  c: *shared"
            $result = Remove-YamlEntry $yaml @('/a/2', '/b/c/0') |
                ConvertFrom-Yaml -AsHashtable

            @($result['a']) | Should -Be @('one')
            [object]::ReferenceEquals($result['a'], $result['b']['c']) |
                Should -BeTrue
        }
    }

    Context 'Aliases, sharing, and cycles' {
        It 'mutates a shared mapping through an alias path' {
            $yaml = @'
root: &shared
  keep: true
  drop: false
copy: *shared
'@
            $result = Remove-YamlEntry $yaml '/copy/drop' |
                ConvertFrom-Yaml -AsHashtable

            $result['root'].Contains('drop') | Should -BeFalse
            $result['copy'].Contains('drop') | Should -BeFalse
            [object]::ReferenceEquals($result['root'], $result['copy']) |
                Should -BeTrue
        }

        It 'removes only an alias edge when that edge is the target' {
            $yaml = @'
root: &shared
  keep: true
copy: *shared
'@
            $result = Remove-YamlEntry $yaml '/copy' |
                ConvertFrom-Yaml -AsHashtable

            $result.Contains('copy') | Should -BeFalse
            $result['root']['keep'] | Should -BeTrue
        }

        It 'traverses a recursive graph safely and preserves its identity' {
            $yaml = @'
node: &node
  self: *node
  keep: true
  drop: false
'@
            $result = Remove-YamlEntry $yaml '/node/self/self/drop' |
                ConvertFrom-Yaml -AsHashtable

            $result['node'].Contains('drop') | Should -BeFalse
            [object]::ReferenceEquals($result['node'], $result['node']['self']) |
                Should -BeTrue
        }

        It 'can remove the alias edge that closes a cycle' {
            $yaml = @'
node: &node
  self: *node
  keep: true
'@
            $result = Remove-YamlEntry $yaml '/node/self' |
                ConvertFrom-Yaml -AsHashtable

            $result['node'].Contains('self') | Should -BeFalse
            $result['node']['keep'] | Should -BeTrue
        }
    }

    Context 'Tags and resulting graph validation' {
        It 'preserves unaffected explicit and unknown tags' {
            $yaml = @'
root: !item
  keep: !!str value
  drop: false
'@
            $actual = Remove-YamlEntry $yaml '/root/drop'

            $actual | Should -Match '!item'
            $actual | Should -Match '!!str'
            $actual | Test-Yaml | Should -BeTrue
        }

        It 'rejects removals that invalidate a tagged collection shape' {
            $yaml = '!!pairs [ { key: value } ]'
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry $yaml '/0/key'
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlInvalidTaggedCollection'
        }

        It 'rejects post-removal duplicate representation keys' -ForEach @(
            @{
                Yaml = @'
cycle: &cycle { self: *cycle }
shared: &shared { x: 1, y: 2 }
? *shared
: first
? { x: 1 }
: second
'@
            }
            @{
                Yaml = @'
shared: &shared { x: 1, y: 2 }
set: !!set
  ? *shared
  ? { x: 1 }
'@
            }
            @{
                Yaml = @'
shared: &shared { x: 1, y: 2 }
ordered: !!omap
  - ? *shared
    : first
  - ? { x: 1 }
    : second
'@
            }
        ) {
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry $Yaml '/shared/y'
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlDuplicateKey'
            $failure.FullyQualifiedErrorId |
                Should -Be 'YamlDuplicateKey,Remove-YamlEntry'
        }
    }

    Context 'Validation and work limits' {
        It 'preserves every parser resource classification' -ForEach @(
            @{ Yaml = "a:`n  b:`n    c: value"; Parameters = @{ Depth = 2 } }
            @{ Yaml = '[one, two]'; Parameters = @{ MaxNodes = 2 } }
            @{ Yaml = "a: &a value`nb: *a"; Parameters = @{ MaxAliases = 0 } }
            @{ Yaml = 'value: long'; Parameters = @{ MaxScalarLength = 4 } }
            @{ Yaml = '!long value'; Parameters = @{ MaxTagLength = 2 } }
            @{
                Yaml       = "!a one`n---`n!b two"
                Parameters = @{ MaxTotalTagLength = 3 }
            }
            @{ Yaml = '123'; Parameters = @{ MaxNumericLength = 2 } }
        ) {
            $parseFailure = Get-RemoveYamlFailure {
                $Yaml | Format-Yaml @Parameters
            }
            $removeFailure = Get-RemoveYamlFailure {
                Remove-YamlEntry $Yaml '' @Parameters
            }

            $removeFailure.Exception.Data['YamlErrorId'] |
                Should -BeExactly $parseFailure.Exception.Data['YamlErrorId']
            $removeFailure.FullyQualifiedErrorId |
                Should -Be "$($parseFailure.Exception.Data['YamlErrorId']),Remove-YamlEntry"
        }

        It 'bounds pointer parsing with the invocation work budget' {
            $failure = Get-RemoveYamlFailure {
                Remove-YamlEntry '{}' '/abcdefghij' -IgnoreMissing -MaxNodes 5
            }

            $failure.Exception.Data['YamlErrorId'] |
                Should -BeExactly 'YamlRemovalWorkLimitExceeded'
            $failure.Exception.Data['YamlRemovalWorkLimit'] | Should -Be 5
        }

        It 'reports deterministic work and produces a result within budget' {
            $measurement = Measure-RemoveYamlWork `
                -Yaml "root:`n  first: 1`n  second: 2`n  third: 3" `
                -Path @('/root/first', '/root/third') `
                -Parameters @{ MaxNodes = 1000 }

            $measurement.Count | Should -BeGreaterThan 0
            $measurement.Count | Should -BeLessOrEqual 1000
            $measurement.Output |
                Should -BeExactly ("root:`n  second: 2" | Format-Yaml)
        }

        It 'applies clone, removal, and output budgets independently' {
            $items = 0..29 | ForEach-Object { "item$_" }
            $yaml = '[' + ($items -join ', ') + ']'

            $result = Remove-YamlEntry $yaml '/0' -MaxNodes 50 |
                ConvertFrom-Yaml

            @($result).Count | Should -Be 29
            $result[0] | Should -BeExactly 'item1'
        }
    }

    Context 'Deterministic representation output' {
        It 'is deterministic, normalized, self-parsing, and leaves input semantics unchanged' {
            $yaml = @'
root: &root
  first: 1
  second: [two, three]
copy: *root
'@
            $before = $yaml | Format-Yaml -Indent 4
            $first = Remove-YamlEntry $yaml @('/root/first', '/copy/second/0') -Indent 4
            $second = Remove-YamlEntry $yaml @('/root/first', '/copy/second/0') -Indent 4

            $second | Should -BeExactly $first
            ($yaml | Format-Yaml -Indent 4) | Should -BeExactly $before
            $first | Test-Yaml | Should -BeTrue
            $first | Should -BeExactly ($first | Format-Yaml -Indent 4)
        }
    }
}
