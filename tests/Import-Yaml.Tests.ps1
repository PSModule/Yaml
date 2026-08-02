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

Describe 'Import-Yaml' {
    Context 'Command contract' {
        It 'declares the Path and LiteralPath parameter sets' {
            $command = Get-Command -Name Import-Yaml
            $pathSet = $command.ParameterSets | Where-Object Name -EQ 'Path'
            $literalPathSet = $command.ParameterSets | Where-Object Name -EQ 'LiteralPath'
            $pathParameter = $pathSet.Parameters | Where-Object Name -EQ 'Path'
            $literalPathParameter = $literalPathSet.Parameters |
                Where-Object Name -EQ 'LiteralPath'

            $command.DefaultParameterSet | Should -Be 'Path'
            @($command.ParameterSets.Name | Sort-Object) | Should -Be @('LiteralPath', 'Path')
            $pathParameter.IsMandatory | Should -BeTrue
            $pathParameter.Position | Should -Be 0
            $pathParameter.ValueFromPipeline | Should -BeTrue
            $pathParameter.ValueFromPipelineByPropertyName | Should -BeFalse
            $literalPathParameter.IsMandatory | Should -BeTrue
            $literalPathParameter.ValueFromPipeline | Should -BeFalse
            $literalPathParameter.ValueFromPipelineByPropertyName | Should -BeTrue
            $command.Parameters['Path'].Aliases | Should -Not -Contain 'FullName'
            $command.Parameters['LiteralPath'].Aliases | Should -Contain 'PSPath'
            $command.Parameters['LiteralPath'].Aliases | Should -Contain 'FullName'
            $command.OutputType.Type | Should -Contain ([object])
        }

        It 'provides complete command help' {
            $help = Get-Help -Name Import-Yaml -Full

            $help.Synopsis | Should -Not -BeNullOrEmpty
            $help.Description.Text | Should -Not -BeNullOrEmpty
            @($help.Examples.Example).Count | Should -BeGreaterOrEqual 2
            @($help.Parameters.Parameter.Name) | Should -Contain 'Path'
            @($help.Parameters.Parameter.Name) | Should -Contain 'LiteralPath'
            @($help.Parameters.Parameter.Name) | Should -Contain 'Encoding'
            $help.returnValues.returnValue.Type.Name | Should -Match 'System\.Object'
        }
    }

    Context 'File selection and document order' {
        It 'accepts any extension and imports every document in file order' {
            $path = Join-Path $TestDrive 'settings.data'
            [System.IO.File]::WriteAllText(
                $path,
                "---`nname: first`n---`nname: second",
                [System.Text.UTF8Encoding]::new($false, $true)
            )

            $result = @(Import-Yaml -Path $path)

            $result.Count | Should -Be 2
            $result[0].name | Should -Be 'first'
            $result[1].name | Should -Be 'second'
        }

        It 'sorts wildcard matches and suppresses duplicate resolved files' {
            $firstPath = Join-Path $TestDrive 'a.yaml'
            $secondPath = Join-Path $TestDrive 'b.yaml'
            [System.IO.File]::WriteAllText($secondPath, 'value: second')
            [System.IO.File]::WriteAllText($firstPath, 'value: first')

            $result = @(
                Import-Yaml -Path @(
                    (Join-Path $TestDrive '*.yaml'),
                    $secondPath,
                    $firstPath
                )
            )

            @($result.value) | Should -Be @('first', 'second')
        }

        It 'keeps case-distinct files separate on case-sensitive filesystems' {
            $upperPath = Join-Path $TestDrive 'Case.yaml'
            $lowerPath = Join-Path $TestDrive 'case.yaml'
            [System.IO.File]::WriteAllText($upperPath, 'value: upper')
            [System.IO.File]::WriteAllText($lowerPath, 'value: lower')
            if ([System.IO.File]::ReadAllText($upperPath) -eq
                [System.IO.File]::ReadAllText($lowerPath)) {
                Set-ItResult -Skipped -Because 'the test filesystem is case-insensitive'
                return
            }

            $result = @(Import-Yaml -Path @($upperPath, $lowerPath))

            @($result.value) | Should -Be @('upper', 'lower')
        }

        It 'suppresses path case variants on case-insensitive filesystems' {
            $path = Join-Path $TestDrive 'CaseVariant.yaml'
            [System.IO.File]::WriteAllText($path, 'value: once')
            $caseVariantPath = Join-Path (
                Split-Path -Parent $path
            ) ([System.IO.Path]::GetFileName($path).ToLowerInvariant())
            try {
                $null = [System.IO.File]::GetAttributes($caseVariantPath)
            } catch [System.IO.FileNotFoundException] {
                Set-ItResult -Skipped -Because 'the test filesystem is case-sensitive'
                return
            } catch [System.IO.DirectoryNotFoundException] {
                Set-ItResult -Skipped -Because 'the test filesystem is case-sensitive'
                return
            }

            $result = @(Import-Yaml -Path @($path, $caseVariantPath))

            $result.Count | Should -Be 1
            $result[0].value | Should -Be 'once'
        }

        It 'suppresses Unicode normalization aliases on matching filesystems' {
            $composedPath = Join-Path $TestDrive "caf$([char] 0x00E9).yaml"
            $decomposedPath = Join-Path $TestDrive "cafe$([char] 0x0301).yaml"
            [System.IO.File]::WriteAllText($composedPath, 'value: once')
            try {
                $null = [System.IO.File]::GetAttributes($decomposedPath)
            } catch [System.IO.FileNotFoundException] {
                Set-ItResult -Skipped -Because (
                    'the test filesystem distinguishes Unicode normalization forms'
                )
                return
            }

            $result = @(Import-Yaml -LiteralPath @($composedPath, $decomposedPath))

            $result.Count | Should -Be 1
            $result[0].value | Should -Be 'once'
        }

        It 'keeps delimiter-bearing Unix paths distinct' -Skip:$IsWindows {
            $separator = [char] 0x001F
            $firstDirectory = Join-Path $TestDrive 'identity-a'
            $secondDirectory = Join-Path $TestDrive "identity-a${separator}identity-b"
            $null = [System.IO.Directory]::CreateDirectory($firstDirectory)
            $null = [System.IO.Directory]::CreateDirectory($secondDirectory)
            $firstPath = Join-Path $firstDirectory "identity-b${separator}value.yaml"
            $secondPath = Join-Path $secondDirectory 'value.yaml'
            [System.IO.File]::WriteAllText($firstPath, 'value: first')
            [System.IO.File]::WriteAllText($secondPath, 'value: second')

            $result = @(Import-Yaml -LiteralPath @($firstPath, $secondPath))

            @($result.value | Sort-Object) | Should -Be @('first', 'second')
        }

        It 'sorts by canonical identity regardless of duplicate path spelling' {
            $firstPath = Join-Path $TestDrive 'canonical-a.yaml'
            $secondPath = Join-Path $TestDrive 'canonical-b.yaml'
            $secondAlias = Join-Path (
                Split-Path -Parent $secondPath
            ) ([System.IO.Path]::GetFileName($secondPath).ToUpperInvariant())
            [System.IO.File]::WriteAllText($firstPath, 'value: first')
            [System.IO.File]::WriteAllText($secondPath, 'value: second')
            try {
                $null = [System.IO.File]::GetAttributes($secondAlias)
            } catch [System.IO.FileNotFoundException] {
                Set-ItResult -Skipped -Because 'the test filesystem is case-sensitive'
                return
            } catch [System.IO.DirectoryNotFoundException] {
                Set-ItResult -Skipped -Because 'the test filesystem is case-sensitive'
                return
            }

            $result = @(Import-Yaml -Path @($secondAlias, $firstPath, $secondPath))

            @($result.value) | Should -Be @('first', 'second')
        }

        It 'normalizes insensitive components around a case-sensitive directory' `
            -Skip:(-not $IsWindows) {
            $caseDirectory = Join-Path $TestDrive 'Sensitive'
            $null = [System.IO.Directory]::CreateDirectory($caseDirectory)
            $null = & fsutil.exe file SetCaseSensitiveInfo $caseDirectory enable 2>&1
            if ($LASTEXITCODE -ne 0) {
                Set-ItResult -Skipped -Because 'per-directory case sensitivity is unavailable'
                return
            }

            $upperPath = Join-Path $caseDirectory 'Case.yaml'
            $lowerPath = Join-Path $caseDirectory 'case.yaml'
            $variantUpperPath = Join-Path (
                Split-Path -Parent $caseDirectory
            ) 'sensitive\Case.yaml'
            [System.IO.File]::WriteAllText($upperPath, 'value: upper')
            [System.IO.File]::WriteAllText($lowerPath, 'value: lower')

            $result = @(Import-Yaml -Path @($upperPath, $variantUpperPath, $lowerPath))

            @($result.value) | Should -Be @('upper', 'lower')
        }

        It 'resolves each relative pipeline path at the location where it arrives' {
            $firstDirectory = Join-Path $TestDrive 'pipeline-a'
            $secondDirectory = Join-Path $TestDrive 'pipeline-b'
            $null = [System.IO.Directory]::CreateDirectory($firstDirectory)
            $null = [System.IO.Directory]::CreateDirectory($secondDirectory)
            [System.IO.File]::WriteAllText(
                (Join-Path $firstDirectory 'config.yaml'),
                'value: first'
            )
            [System.IO.File]::WriteAllText(
                (Join-Path $secondDirectory 'config.yaml'),
                'value: second'
            )

            $result = @(
                & {
                    Push-Location $firstDirectory
                    try {
                        Write-Output 'config.yaml'
                        Set-Location $secondDirectory
                        Write-Output 'config.yaml'
                    } finally {
                        Pop-Location
                    }
                } | Import-Yaml
            )

            @($result.value) | Should -Be @('first', 'second')
        }

        It 'preserves deterministic file and document order together' {
            $firstPath = Join-Path $TestDrive '01.yaml'
            $secondPath = Join-Path $TestDrive '02.yaml'
            [System.IO.File]::WriteAllText(
                $secondPath,
                "---`nvalue: three`n---`nvalue: four"
            )
            [System.IO.File]::WriteAllText(
                $firstPath,
                "---`nvalue: one`n---`nvalue: two"
            )

            $result = @(Import-Yaml -Path (Join-Path $TestDrive '0?.yaml'))

            @($result.value) | Should -Be @('one', 'two', 'three', 'four')
        }

        It 'treats wildcard characters literally with LiteralPath' {
            $path = Join-Path $TestDrive 'settings[1].data'
            [System.IO.File]::WriteAllText($path, 'value: literal')
            [System.IO.File]::WriteAllText(
                (Join-Path $TestDrive 'settings1.data'),
                'value: wildcard'
            )

            (Import-Yaml -LiteralPath $path).value | Should -Be 'literal'
        }

        It 'resolves FileInfo pipeline input literally' {
            $path = Join-Path $TestDrive 'config[production].yaml'
            [System.IO.File]::WriteAllText($path, 'value: pipeline')

            $result = Get-Item -LiteralPath $path | Import-Yaml

            $result.value | Should -Be 'pipeline'
        }

        It 'resolves FullName pipeline properties literally' {
            $path = Join-Path $TestDrive 'full[name].yaml'
            [System.IO.File]::WriteAllText($path, 'value: fullname')

            $result = [pscustomobject]@{ FullName = $path } | Import-Yaml

            $result.value | Should -Be 'fullname'
        }

        It 'accepts PSPath pipeline properties through LiteralPath' {
            $path = Join-Path $TestDrive 'literal[2].yaml'
            [System.IO.File]::WriteAllText($path, 'value: property')
            $item = Get-Item -LiteralPath $path

            $result = [pscustomobject]@{ PSPath = $item.PSPath } | Import-Yaml

            $result.value | Should -Be 'property'
        }

        It 'preserves each root sequence as one record with NoEnumerate' {
            $path = Join-Path $TestDrive 'sequence.yaml'
            [System.IO.File]::WriteAllText($path, "- one`n- two")

            $result = Import-Yaml -Path $path -NoEnumerate

            , $result | Should -BeOfType [object[]]
            $result | Should -Be @('one', 'two')
        }

        It 'emits no documents for an empty file' {
            $path = Join-Path $TestDrive 'empty.yaml'
            [System.IO.File]::WriteAllBytes($path, [byte[]]::new(0))

            @(Import-Yaml -Path $path).Count | Should -Be 0
        }
    }

    Context 'Strict text decoding' {
        It 'imports BOM-less <Name> text with the selected encoding' -ForEach @(
            @{
                Name         = 'utf8'
                EncodingName = 'utf8'
                Encoding     = [System.Text.UTF8Encoding]::new($false, $true)
            }
            @{
                Name         = 'utf8BOM'
                EncodingName = 'utf8BOM'
                Encoding     = [System.Text.UTF8Encoding]::new($false, $true)
            }
            @{
                Name         = 'utf16LE'
                EncodingName = 'utf16LE'
                Encoding     = [System.Text.UnicodeEncoding]::new($false, $false, $true)
            }
            @{
                Name         = 'utf16BE'
                EncodingName = 'utf16BE'
                Encoding     = [System.Text.UnicodeEncoding]::new($true, $false, $true)
            }
            @{
                Name         = 'utf32LE'
                EncodingName = 'utf32LE'
                Encoding     = [System.Text.UTF32Encoding]::new($false, $false, $true)
            }
            @{
                Name         = 'utf32BE'
                EncodingName = 'utf32BE'
                Encoding     = [System.Text.UTF32Encoding]::new($true, $false, $true)
            }
        ) {
            $path = Join-Path $TestDrive "$Name.data"
            $text = "value: caf$([char] 0xE9)"
            [System.IO.File]::WriteAllBytes($path, $Encoding.GetBytes($text))

            (Import-Yaml -Path $path -Encoding $EncodingName).value | Should -Be "caf$([char] 0xE9)"
        }

        It 'detects a <Name> BOM and lets it override the selected encoding' -ForEach @(
            @{
                Name         = 'utf8'
                EncodingName = 'utf16BE'
                Encoding     = [System.Text.UTF8Encoding]::new($true, $true)
            }
            @{
                Name         = 'utf16LE'
                EncodingName = 'utf8'
                Encoding     = [System.Text.UnicodeEncoding]::new($false, $true, $true)
            }
            @{
                Name         = 'utf16BE'
                EncodingName = 'utf8'
                Encoding     = [System.Text.UnicodeEncoding]::new($true, $true, $true)
            }
            @{
                Name         = 'utf32LE'
                EncodingName = 'utf8'
                Encoding     = [System.Text.UTF32Encoding]::new($false, $true, $true)
            }
            @{
                Name         = 'utf32BE'
                EncodingName = 'utf8'
                Encoding     = [System.Text.UTF32Encoding]::new($true, $true, $true)
            }
        ) {
            $path = Join-Path $TestDrive "$Name-bom.data"
            $payload = [byte[]] (
                $Encoding.GetPreamble() +
                $Encoding.GetBytes("value: caf$([char] 0xE9)")
            )
            [System.IO.File]::WriteAllBytes($path, $payload)

            (Import-Yaml -Path $path -Encoding $EncodingName).value | Should -Be "caf$([char] 0xE9)"
        }

        It 'defaults to strict BOM-less UTF-8' {
            $path = Join-Path $TestDrive 'default-utf8.yaml'
            $encoding = [System.Text.UTF8Encoding]::new($false, $true)
            [System.IO.File]::WriteAllBytes(
                $path,
                $encoding.GetBytes("value: caf$([char] 0xE9)")
            )

            (Import-Yaml -Path $path).value | Should -Be "caf$([char] 0xE9)"
        }

        It 'rejects malformed bytes with a path-specific encoding error' {
            $path = Join-Path $TestDrive 'malformed.yaml'
            [System.IO.File]::WriteAllBytes($path, [byte[]] @(0xC3, 0x28))

            try {
                Import-Yaml -Path $path
                throw 'Expected Import-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlImportEncodingFailed,Import-Yaml'
                $_.CategoryInfo.Category | Should -Be 'InvalidData'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }
        }
    }

    Context 'Parser controls' {
        It 'passes AsHashtable and every parser limit through' {
            $path = Join-Path $TestDrive 'mapping.yaml'
            [System.IO.File]::WriteAllText($path, "outer:`n  value: 12")

            $result = Import-Yaml -Path $path -AsHashtable -Depth 3 -MaxNodes 5 `
                -MaxAliases 0 -MaxScalarLength 5 -MaxTagLength 3 `
                -MaxTotalTagLength 3 -MaxNumericLength 2

            $result | Should -BeOfType [System.Collections.Specialized.OrderedDictionary]
            $result['outer']['value'] | Should -Be 12
        }

        It 'preserves parser limit classifications and identifies the path' {
            $path = Join-Path $TestDrive 'limited.yaml'
            [System.IO.File]::WriteAllText($path, "[one, two]")

            try {
                Import-Yaml -Path $path -MaxNodes 2
                throw 'Expected Import-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlNodeLimitExceeded,Import-Yaml'
                $_.CategoryInfo.Category | Should -Be 'InvalidData'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }
        }
    }

    Context 'Classified failures' {
        It 'classifies a missing literal path' {
            $path = Join-Path $TestDrive 'missing.yaml'

            try {
                Import-Yaml -LiteralPath $path
                throw 'Expected Import-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlImportPathNotFound,Import-Yaml'
                $_.CategoryInfo.Category | Should -Be 'ObjectNotFound'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }
        }

        It 'classifies an unresolved wildcard path' {
            $path = Join-Path $TestDrive '*.missing'

            try {
                Import-Yaml -Path $path
                throw 'Expected Import-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlImportPathNotFound,Import-Yaml'
                $_.CategoryInfo.Category | Should -Be 'ObjectNotFound'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }
        }

        It 'rejects non-FileSystem providers' {
            try {
                Import-Yaml -LiteralPath 'Env:PATH'
                throw 'Expected Import-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlImportProviderNotSupported,Import-Yaml'
                $_.CategoryInfo.Category | Should -Be 'InvalidArgument'
                $_.Exception.Message | Should -Match 'Env:PATH'
            }
        }

        It 'rejects directories' {
            $path = Join-Path $TestDrive 'directory'
            $null = [System.IO.Directory]::CreateDirectory($path)

            try {
                Import-Yaml -LiteralPath $path
                throw 'Expected Import-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Be 'YamlImportNotFile,Import-Yaml'
                $_.CategoryInfo.Category | Should -Be 'InvalidType'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }
        }

        It 'classifies file read failures' {
            $path = Join-Path $TestDrive 'locked.yaml'
            [System.IO.File]::WriteAllText($path, 'value: locked')
            $stream = [System.IO.File]::Open(
                $path,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::ReadWrite,
                [System.IO.FileShare]::None
            )
            try {
                try {
                    Import-Yaml -LiteralPath $path
                    throw 'Expected Import-Yaml to terminate.'
                } catch {
                    $_.FullyQualifiedErrorId | Should -Be 'YamlImportReadFailed,Import-Yaml'
                    $_.CategoryInfo.Category | Should -Be 'ReadError'
                    $_.Exception.Message | Should -Match ([regex]::Escape($path))
                }
            } finally {
                $stream.Dispose()
            }
        }

        It 'preserves parser classifications and identifies the path' {
            $path = Join-Path $TestDrive 'invalid.yaml'
            [System.IO.File]::WriteAllText($path, '[unterminated')

            try {
                Import-Yaml -Path $path
                throw 'Expected Import-Yaml to terminate.'
            } catch {
                $_.FullyQualifiedErrorId | Should -Match '^Yaml.+,Import-Yaml$'
                $_.CategoryInfo.Category | Should -Be 'InvalidData'
                $_.Exception.Message | Should -Match ([regex]::Escape($path))
            }
        }
    }
}
