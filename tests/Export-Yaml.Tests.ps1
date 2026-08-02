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

Describe 'Export-Yaml' {
    Context 'Command contract' {
        It 'declares pipeline, ShouldProcess, and output metadata' {
            $command = Get-Command -Name Export-Yaml
            $binding = $command.ScriptBlock.Attributes |
                Where-Object { $_ -is [System.Management.Automation.CmdletBindingAttribute] }
            $inputParameter = $command.ParameterSets.Parameters |
                Where-Object Name -EQ 'InputObject' |
                Select-Object -First 1
            $pathParameter = $command.ParameterSets.Parameters |
                Where-Object Name -EQ 'Path' |
                Select-Object -First 1

            $binding.SupportsShouldProcess | Should -BeTrue
            $binding.ConfirmImpact | Should -Be ([System.Management.Automation.ConfirmImpact]::Medium)
            $inputParameter.IsMandatory | Should -BeTrue
            $inputParameter.Position | Should -Be 0
            $inputParameter.ValueFromPipeline | Should -BeTrue
            $pathParameter.IsMandatory | Should -BeTrue
            $pathParameter.Position | Should -Be 1
            $command.OutputType.Type | Should -Contain ([System.IO.FileInfo])
            $command.Parameters['Encoding'].Attributes.ValidValues |
                Should -Be @('utf8', 'utf8BOM', 'utf16LE', 'utf16BE', 'utf32LE', 'utf32BE')
            $command.Parameters['NewLine'].Attributes.ValidValues | Should -Be @('LF', 'CRLF')
        }

        It 'provides complete command help' {
            $help = Get-Help -Name Export-Yaml -Full

            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description.Text | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 3
            @($help.Parameters.Parameter.Name) | Should -Contain 'InputObject'
            @($help.Parameters.Parameter.Name) | Should -Contain 'Path'
            @($help.Parameters.Parameter.Name) | Should -Contain 'NoClobber'
            @($help.Parameters.Parameter.Name) | Should -Contain 'Force'
            $help.returnValues.returnValue.Type.Name | Should -Match 'System\.IO\.FileInfo'
        }
    }

    Context 'Pipeline aggregation and serializer controls' {
        It 'serializes one direct array as one input value' {
            $path = Join-Path $TestDrive 'direct-array.yaml'
            $items = @('one', 'two')

            Export-Yaml -InputObject $items -Path $path
            $result = Import-Yaml -Path $path -NoEnumerate

            , $result | Should -BeOfType [object[]]
            $result | Should -Be @('one', 'two')
        }

        It 'preserves an explicit one-element array as a sequence' {
            $path = Join-Path $TestDrive 'one-element-array.yaml'

            Export-Yaml -InputObject @(42) -Path $path

            [System.IO.File]::ReadAllText($path) | Should -Be "- 42`n"
        }

        It 'preserves an explicit empty array as an empty sequence' {
            $path = Join-Path $TestDrive 'empty-array.yaml'

            Export-Yaml -InputObject @() -Path $path

            [System.IO.File]::ReadAllText($path) | Should -Be "[]`n"
        }

        It 'collects multiple pipeline records into one sequence' {
            $path = Join-Path $TestDrive 'pipeline.yaml'

            'one', 'two', 'three' | Export-Yaml -Path $path
            $result = Import-Yaml -Path $path -NoEnumerate

            $result | Should -Be @('one', 'two', 'three')
        }

        It 'distinguishes one nested pipeline record from multiple records' {
            $singlePath = Join-Path $TestDrive 'single-nested-record.yaml'
            $multiplePath = Join-Path $TestDrive 'multiple-nested-records.yaml'
            $firstRecord = [object[]]::new(1)
            $firstRecord[0] = [object[]] @(1, 2)
            $secondRecord = [object[]]::new(1)
            $secondRecord[0] = [object[]] @(3, 4)

            Write-Output -InputObject $firstRecord -NoEnumerate |
                Export-Yaml -Path $singlePath
            & {
                Write-Output -InputObject $firstRecord -NoEnumerate
                Write-Output -InputObject $secondRecord -NoEnumerate
            } | Export-Yaml -Path $multiplePath

            $singleExpected = ConvertTo-Yaml -InputObject $firstRecord
            $multipleExpected = & {
                Write-Output -InputObject $firstRecord -NoEnumerate
                Write-Output -InputObject $secondRecord -NoEnumerate
            } | ConvertTo-Yaml
            [System.IO.File]::ReadAllText($singlePath) | Should -Be $singleExpected
            [System.IO.File]::ReadAllText($multiplePath) | Should -Be $multipleExpected
        }

        It 'serializes an explicit null input' {
            $path = Join-Path $TestDrive 'null.yaml'

            Export-Yaml -InputObject $null -Path $path

            [System.IO.File]::ReadAllText($path) | Should -Be "null`n"
        }

        It 'passes serializer formatting controls through' {
            $path = Join-Path $TestDrive 'format.yaml'
            $inputObject = [ordered]@{
                nested = [ordered]@{ day = [DayOfWeek]::Monday }
            }

            Export-Yaml -InputObject $inputObject -Path $path -Depth 3 -MaxNodes 5 `
                -MaxScalarLength 6 -Indent 4 -ExplicitDocumentStart -EnumsAsStrings
            $text = [System.IO.File]::ReadAllText($path)
            $result = Import-Yaml -Path $path

            $text | Should -Match '^---\n'
            $text | Should -Match '(?m)^ {4}"day": "Monday"$'
            $result.nested.day | Should -Be 'Monday'
        }

        It 'preserves an existing destination when serialization fails' {
            $path = Join-Path $TestDrive 'serialization-failure.yaml'
            [System.IO.File]::WriteAllText($path, "original`n")

            try {
                Export-Yaml -InputObject ([uri] 'https://example.com') -Path $path
                throw 'Expected Export-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlUnsupportedType,Export-Yaml'
                $_.CategoryInfo.Category | Should -Be 'InvalidType'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }
            [System.IO.File]::ReadAllText($path) | Should -Be "original`n"
            @(Get-ChildItem -LiteralPath $TestDrive -Filter '.yaml-*.tmp').Count | Should -Be 0
        }

        It 'classifies malformed text serialization and preserves the destination' {
            $path = Join-Path $TestDrive 'malformed-text.yaml'
            [System.IO.File]::WriteAllText($path, "original`n")

            try {
                Export-Yaml -InputObject ([string] [char] 0xD800) -Path $path
                throw 'Expected Export-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId |
                    Should -Be 'YamlExportSerializationFailed,Export-Yaml'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }

            [System.IO.File]::ReadAllText($path) | Should -Be "original`n"
            @(Get-ChildItem -LiteralPath $TestDrive -Filter '.yaml-*.tmp').Count | Should -Be 0
        }

        It 'preserves serializer resource-limit classifications and the destination' {
            $path = Join-Path $TestDrive 'limit-failure.yaml'
            [System.IO.File]::WriteAllText($path, "original`n")

            try {
                @('one', 'two') | Export-Yaml -Path $path -MaxNodes 2
                throw 'Expected Export-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlNodeLimitExceeded,Export-Yaml'
                $_.CategoryInfo.Category | Should -Be 'InvalidOperation'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }
            [System.IO.File]::ReadAllText($path) | Should -Be "original`n"
        }

        It 'enforces serializer limits while pipeline records arrive' {
            $path = Join-Path $TestDrive 'bounded-pipeline.yaml'
            $script:producedRecordCount = 0

            try {
                1..25 | ForEach-Object {
                    $script:producedRecordCount++
                    $_
                } | Export-Yaml -Path $path -MaxNodes 1
                throw 'Expected Export-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlNodeLimitExceeded,Export-Yaml'
            }

            $script:producedRecordCount | Should -Be 2
            Test-Path -LiteralPath $path | Should -BeFalse
        }
    }

    Context 'Strict output encoding' {
        It 'writes exact <Name> preamble bytes and strict encoded text' -ForEach @(
            @{
                Name             = 'utf8'
                ExpectedPreamble = [byte[]] @()
                Decoder          = [System.Text.UTF8Encoding]::new($false, $true)
            }
            @{
                Name             = 'utf8BOM'
                ExpectedPreamble = [byte[]] @(0xEF, 0xBB, 0xBF)
                Decoder          = [System.Text.UTF8Encoding]::new($false, $true)
            }
            @{
                Name             = 'utf16LE'
                ExpectedPreamble = [byte[]] @(0xFF, 0xFE)
                Decoder          = [System.Text.UnicodeEncoding]::new($false, $false, $true)
            }
            @{
                Name             = 'utf16BE'
                ExpectedPreamble = [byte[]] @(0xFE, 0xFF)
                Decoder          = [System.Text.UnicodeEncoding]::new($true, $false, $true)
            }
            @{
                Name             = 'utf32LE'
                ExpectedPreamble = [byte[]] @(0xFF, 0xFE, 0x00, 0x00)
                Decoder          = [System.Text.UTF32Encoding]::new($false, $false, $true)
            }
            @{
                Name             = 'utf32BE'
                ExpectedPreamble = [byte[]] @(0x00, 0x00, 0xFE, 0xFF)
                Decoder          = [System.Text.UTF32Encoding]::new($true, $false, $true)
            }
        ) {
            $path = Join-Path $TestDrive "$Name-output.yaml"
            $value = "caf$([char] 0xE9)"
            $inputObject = [ordered]@{ value = $value }

            Export-Yaml -InputObject $inputObject -Path $path -Encoding $Name
            $bytes = [System.IO.File]::ReadAllBytes($path)
            if ($ExpectedPreamble.Count -eq 0) {
                @($bytes[0..2]) | Should -Not -Be @([byte] 0xEF, [byte] 0xBB, [byte] 0xBF)
            } else {
                @($bytes[0..($ExpectedPreamble.Count - 1)]) | Should -Be $ExpectedPreamble
            }
            $text = $Decoder.GetString(
                $bytes,
                $ExpectedPreamble.Count,
                $bytes.Length - $ExpectedPreamble.Count
            )

            $text | Should -Be (ConvertTo-Yaml -InputObject $inputObject)
            (Import-Yaml -Path $path).value | Should -Be $value
        }
    }

    Context 'Line ending policy' {
        It 'writes LF with exactly one final newline by default' {
            $path = Join-Path $TestDrive 'lf.yaml'

            Export-Yaml -InputObject ([ordered]@{ value = 'text' }) -Path $path
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString(
                [System.IO.File]::ReadAllBytes($path)
            )

            $text | Should -Be (
                ConvertTo-Yaml -InputObject ([ordered]@{ value = 'text' })
            )
            $text.EndsWith("`n") | Should -BeTrue
            $text.EndsWith("`n`n") | Should -BeFalse
            $text.Contains("`r") | Should -BeFalse
        }

        It 'writes CRLF without changing escaped multiline scalar content' {
            $path = Join-Path $TestDrive 'crlf.yaml'
            $inputObject = [ordered]@{
                multiline = "one`ntwo"
                value     = 'text'
            }

            Export-Yaml -InputObject $inputObject -Path $path -NewLine CRLF
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString(
                [System.IO.File]::ReadAllBytes($path)
            )
            $result = Import-Yaml -Path $path

            $text | Should -Not -Match '(?<!\r)\n'
            $text | Should -Match '\\n'
            $text.EndsWith("`r`n") | Should -BeTrue
            $text.EndsWith("`r`n`r`n") | Should -BeFalse
            $result.multiline | Should -Be $inputObject.multiline
        }

        It 'omits the final newline when requested' {
            $path = Join-Path $TestDrive 'no-final-newline.yaml'

            Export-Yaml -InputObject 'value' -Path $path -NewLine CRLF -NoFinalNewline
            $text = [System.Text.UTF8Encoding]::new($false, $true).GetString(
                [System.IO.File]::ReadAllBytes($path)
            )

            $text | Should -Be '"value"'
            $text.EndsWith("`n") | Should -BeFalse
            $text.EndsWith("`r") | Should -BeFalse
        }
    }

    Context 'Destination controls' {
        It 'overwrites an existing writable file by default and emits no output' {
            $path = Join-Path $TestDrive 'overwrite.yaml'
            [System.IO.File]::WriteAllText($path, "old`n")

            $output = Export-Yaml -InputObject 'new' -Path $path

            $output | Should -BeNullOrEmpty
            [System.IO.File]::ReadAllText($path) | Should -Be "`"new`"`n"
        }

        It 'prevents overwrite with NoClobber' {
            $path = Join-Path $TestDrive 'no-clobber.yaml'
            [System.IO.File]::WriteAllText($path, "old`n")

            try {
                Export-Yaml -InputObject 'new' -Path $path -NoClobber
                throw 'Expected Export-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlExportDestinationExists,Export-Yaml'
                $_.CategoryInfo.Category | Should -Be 'ResourceExists'
            }
            [System.IO.File]::ReadAllText($path) | Should -Be "old`n"
        }

        It 'publishes a new NoClobber destination without a temporary file' {
            $path = Join-Path $TestDrive 'no-clobber-new.yaml'

            Export-Yaml -InputObject 'new' -Path $path -NoClobber

            [System.IO.File]::ReadAllText($path) | Should -Be "`"new`"`n"
            @(Get-ChildItem -LiteralPath $TestDrive -Filter '.yaml-*.tmp' -Force).Count |
                Should -Be 0
        }

        It 'rejects Force together with NoClobber' {
            $path = Join-Path $TestDrive 'conflicting-options.yaml'

            try {
                Export-Yaml -InputObject 'value' -Path $path -NoClobber -Force
                throw 'Expected Export-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId |
                    Should -Be 'YamlExportConflictingFileOptions,Export-Yaml'
                $_.CategoryInfo.Category | Should -Be 'InvalidArgument'
            }
            Test-Path -LiteralPath $path | Should -BeFalse
        }

        It 'requires Force for a read-only destination and preserves that attribute' {
            $path = Join-Path $TestDrive 'read-only.yaml'
            [System.IO.File]::WriteAllText($path, "old`n")
            $originalAttributes = [System.IO.File]::GetAttributes($path)
            [System.IO.File]::SetAttributes(
                $path,
                $originalAttributes -bor [System.IO.FileAttributes]::ReadOnly
            )
            try {
                try {
                    Export-Yaml -InputObject 'new' -Path $path
                    throw 'Expected Export-Yaml to terminate.'
                } catch {
                    $_.FullyQualifiedErrorId |
                        Should -Be 'YamlExportDestinationReadOnly,Export-Yaml'
                    $_.CategoryInfo.Category | Should -Be 'PermissionDenied'
                }
                [System.IO.File]::ReadAllText($path) | Should -Be "old`n"

                Export-Yaml -InputObject 'new' -Path $path -Force

                [System.IO.File]::ReadAllText($path) | Should -Be "`"new`"`n"
                (
                    [System.IO.File]::GetAttributes($path) -band
                    [System.IO.FileAttributes]::ReadOnly
                ) | Should -Be ([System.IO.FileAttributes]::ReadOnly)
            } finally {
                if ([System.IO.File]::Exists($path)) {
                    [System.IO.File]::SetAttributes($path, $originalAttributes)
                }
            }
        }

        It 'preserves destination security metadata across replacement' {
            $path = Join-Path $TestDrive 'metadata.yaml'
            [System.IO.File]::WriteAllText($path, "old`n")
            if ($IsWindows) {
                $sections = (
                    [System.Security.AccessControl.AccessControlSections]::Access
                )
                $security = [System.IO.FileSystemAclExtensions]::GetAccessControl(
                    [System.IO.FileInfo]::new($path),
                    $sections
                )
                $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
                $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                    $identity,
                    [System.Security.AccessControl.FileSystemRights]::ReadData,
                    [System.Security.AccessControl.AccessControlType]::Deny
                )
                $null = $security.AddAccessRule($rule)
                [System.IO.FileSystemAclExtensions]::SetAccessControl(
                    [System.IO.FileInfo]::new($path),
                    $security
                )
                $before = [System.IO.FileSystemAclExtensions]::GetAccessControl(
                    [System.IO.FileInfo]::new($path),
                    $sections
                ).GetSecurityDescriptorSddlForm(
                    $sections
                )
            } else {
                $expectedMode = (
                    [System.IO.UnixFileMode]::UserRead -bor
                    [System.IO.UnixFileMode]::UserWrite
                )
                [System.IO.File]::SetUnixFileMode($path, $expectedMode)
            }

            Export-Yaml -InputObject 'new' -Path $path

            if ($IsWindows) {
                $after = [System.IO.FileSystemAclExtensions]::GetAccessControl(
                    [System.IO.FileInfo]::new($path),
                    $sections
                ).GetSecurityDescriptorSddlForm(
                    $sections
                )
                $after | Should -Be $before
            } else {
                [System.IO.File]::GetUnixFileMode($path) | Should -Be $expectedMode
            }
        }

        It 'preserves Unix special mode bits after writing' -Skip:$IsWindows {
            $path = Join-Path $TestDrive 'special-mode.yaml'
            [System.IO.File]::WriteAllText($path, "old`n")
            $expectedMode = (
                [System.IO.UnixFileMode]::UserRead -bor
                [System.IO.UnixFileMode]::UserWrite -bor
                [System.IO.UnixFileMode]::GroupRead -bor
                [System.IO.UnixFileMode]::SetUser -bor
                [System.IO.UnixFileMode]::SetGroup
            )
            [System.IO.File]::SetUnixFileMode($path, $expectedMode)
            if ([System.IO.File]::GetUnixFileMode($path) -ne $expectedMode) {
                Set-ItResult -Skipped -Because 'the test filesystem rejects special mode bits'
                return
            }

            Export-Yaml -InputObject 'new' -Path $path

            [System.IO.File]::GetUnixFileMode($path) | Should -Be $expectedMode
        }

        It 'restores read-only attributes on hard-link siblings after Force' -Skip:(-not $IsWindows) {
            $path = Join-Path $TestDrive 'linked-read-only.yaml'
            $siblingPath = Join-Path $TestDrive 'linked-read-only-sibling.yaml'
            [System.IO.File]::WriteAllText($path, "old`n")
            $null = New-Item -ItemType HardLink -Path $siblingPath -Target $path
            $originalAttributes = [System.IO.File]::GetAttributes($path)
            [System.IO.File]::SetAttributes(
                $path,
                $originalAttributes -bor [System.IO.FileAttributes]::ReadOnly
            )
            try {
                Export-Yaml -InputObject 'new' -Path $path -Force

                [System.IO.File]::ReadAllText($path) | Should -Be "`"new`"`n"
                [System.IO.File]::ReadAllText($siblingPath) | Should -Be "old`n"
                (
                    [System.IO.File]::GetAttributes($siblingPath) -band
                    [System.IO.FileAttributes]::ReadOnly
                ) | Should -Be ([System.IO.FileAttributes]::ReadOnly)
            } finally {
                foreach ($linkedPath in @($path, $siblingPath)) {
                    if ([System.IO.File]::Exists($linkedPath)) {
                        [System.IO.File]::SetAttributes($linkedPath, $originalAttributes)
                    }
                }
            }
        }

        It 'creates missing parent directories only when requested' {
            $path = Join-Path $TestDrive 'nested/one/two/output.yaml'

            Export-Yaml -InputObject 'value' -Path $path -CreateDirectory

            [System.IO.File]::ReadAllText($path) | Should -Be "`"value`"`n"
        }

        It 'classifies a missing parent directory without CreateDirectory' {
            $path = Join-Path $TestDrive 'missing/parent/output.yaml'

            try {
                Export-Yaml -InputObject 'value' -Path $path
                throw 'Expected Export-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlExportDirectoryNotFound,Export-Yaml'
                $_.CategoryInfo.Category | Should -Be 'ObjectNotFound'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }
        }

        It 'does not create a directory, file, or temporary file under WhatIf' {
            $directory = Join-Path $TestDrive 'what-if/nested'
            $path = Join-Path $directory 'output.yaml'

            $output = Export-Yaml -InputObject 'value' -Path $path -CreateDirectory `
                -PassThru -WhatIf

            $output | Should -BeNullOrEmpty
            Test-Path -LiteralPath $directory | Should -BeFalse
            Test-Path -LiteralPath $path | Should -BeFalse
        }

        It 'returns the final FileInfo only with PassThru' {
            $path = Join-Path $TestDrive 'pass-thru.yaml'

            $result = Export-Yaml -InputObject 'value' -Path $path -PassThru

            $result | Should -BeOfType [System.IO.FileInfo]
            $result.FullName | Should -Be ([System.IO.Path]::GetFullPath($path))
        }

        It 'treats wildcard characters in Path literally' {
            $path = Join-Path $TestDrive 'output[1].yaml'
            [System.IO.File]::WriteAllText(
                (Join-Path $TestDrive 'output1.yaml'),
                "unchanged`n"
            )

            Export-Yaml -InputObject 'literal' -Path $path

            [System.IO.File]::ReadAllText($path) | Should -Be "`"literal`"`n"
            [System.IO.File]::ReadAllText(
                (Join-Path $TestDrive 'output1.yaml')
            ) | Should -Be "unchanged`n"
        }
    }

    Context 'Atomic file failures' {
        It 'preserves the destination and cleans temporary files after a write failure' {
            $directory = Join-Path $TestDrive 'write-denied'
            $null = [System.IO.Directory]::CreateDirectory($directory)
            $path = Join-Path $directory 'output.yaml'
            [System.IO.File]::WriteAllText($path, "original`n")

            if ($IsWindows) {
                $acl = Get-Acl -LiteralPath $directory
                $originalSddl = $acl.GetSecurityDescriptorSddlForm(
                    [System.Security.AccessControl.AccessControlSections]::All
                )
                $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
                $rule = [System.Security.AccessControl.FileSystemAccessRule]::new(
                    $identity,
                    [System.Security.AccessControl.FileSystemRights]::CreateFiles,
                    [System.Security.AccessControl.AccessControlType]::Deny
                )
                $null = $acl.AddAccessRule($rule)
                Set-Acl -LiteralPath $directory -AclObject $acl
            } else {
                $originalMode = [System.IO.File]::GetUnixFileMode($directory)
                [System.IO.File]::SetUnixFileMode(
                    $directory,
                    [System.IO.UnixFileMode]::UserRead -bor
                    [System.IO.UnixFileMode]::UserExecute
                )
            }

            try {
                try {
                    Export-Yaml -InputObject 'replacement' -Path $path
                    throw 'Expected Export-Yaml to terminate.'
                } catch {
                    $_.FullyQualifiedErrorId | Should -Be 'YamlExportWriteFailed,Export-Yaml'
                    $_.CategoryInfo.Category | Should -Be 'WriteError'
                }
            } finally {
                if ($IsWindows) {
                    $restoredAcl = [System.Security.AccessControl.DirectorySecurity]::new()
                    $restoredAcl.SetSecurityDescriptorSddlForm($originalSddl)
                    Set-Acl -LiteralPath $directory -AclObject $restoredAcl
                } else {
                    [System.IO.File]::SetUnixFileMode($directory, $originalMode)
                }
            }

            [System.IO.File]::ReadAllText($path) | Should -Be "original`n"
            @(Get-ChildItem -LiteralPath $directory -Filter '.yaml-*.tmp' -Force).Count |
                Should -Be 0
        }

        It 'preserves the destination and cleans temporary files after replace failure' `
            -Skip:(-not $IsWindows) {
            $path = Join-Path $TestDrive 'replace-locked.yaml'
            [System.IO.File]::WriteAllText($path, "original`n")
            $stream = [System.IO.File]::Open(
                $path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read
            )
            try {
                try {
                    Export-Yaml -InputObject 'replacement' -Path $path
                    throw 'Expected Export-Yaml to terminate.'
                } catch {
                    $_.FullyQualifiedErrorId | Should -Be 'YamlExportReplaceFailed,Export-Yaml'
                    $_.CategoryInfo.Category | Should -Be 'PermissionDenied'
                }
            } finally {
                $stream.Dispose()
            }

            [System.IO.File]::ReadAllText($path) | Should -Be "original`n"
            @(Get-ChildItem -LiteralPath $TestDrive -Filter '.yaml-*.tmp' -Force).Count |
                Should -Be 0
            @(Get-ChildItem -LiteralPath $TestDrive -Filter '.yaml-*.old' -Force).Count |
                Should -Be 0
        }

        It 'restores a read-only destination when native replacement does not move it' `
            -Skip:(-not $IsWindows) {
            $path = Join-Path $TestDrive 'read-only-replace-locked.yaml'
            [System.IO.File]::WriteAllText($path, "original`n")
            $attributes = [System.IO.File]::GetAttributes($path)
            [System.IO.File]::SetAttributes(
                $path,
                $attributes -bor [System.IO.FileAttributes]::ReadOnly
            )
            $stream = [System.IO.File]::Open(
                $path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read
            )
            try {
                try {
                    Export-Yaml -InputObject 'replacement' -Path $path -Force
                    throw 'Expected Export-Yaml to terminate.'
                } catch {
                    $_.FullyQualifiedErrorId | Should -Be 'YamlExportReplaceFailed,Export-Yaml'
                }
            } finally {
                $stream.Dispose()
            }

            [System.IO.File]::ReadAllText($path) | Should -Be "original`n"
            (
                [System.IO.File]::GetAttributes($path) -band
                [System.IO.FileAttributes]::ReadOnly
            ) | Should -Be ([System.IO.FileAttributes]::ReadOnly)
            @(Get-ChildItem -LiteralPath $TestDrive -Filter '.yaml-*.tmp' -Force).Count |
                Should -Be 0
            @(Get-ChildItem -LiteralPath $TestDrive -Filter '.yaml-*.old' -Force).Count |
                Should -Be 0
        }
    }

    Context 'Classified path failures' {
        It 'rejects non-FileSystem providers' {
            try {
                Export-Yaml -InputObject 'value' -Path 'Env:yaml-output'
                throw 'Expected Export-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlExportProviderNotSupported,Export-Yaml'
                $_.CategoryInfo.Category | Should -Be 'InvalidArgument'
                $_.Exception.Message | Should -Match 'Env:yaml-output'
            }
        }

        It 'rejects a directory destination' {
            $path = Join-Path $TestDrive 'directory-destination'
            $null = [System.IO.Directory]::CreateDirectory($path)

            try {
                Export-Yaml -InputObject 'value' -Path $path
                throw 'Expected Export-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlExportNotFile,Export-Yaml'
                $_.CategoryInfo.Category | Should -Be 'InvalidType'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }
        }
    }
}
