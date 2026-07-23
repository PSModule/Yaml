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

$importedYamlCommand = Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue
$skipArtifactTests = [string]::IsNullOrWhiteSpace($env:PSMODULE_YAML_TEST_ARTIFACT) -and (
    $null -eq $importedYamlCommand -or $importedYamlCommand.ModuleName -ne 'Yaml'
)

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestBootstrap.ps1')
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $loadedYamlModule = if (-not [string]::IsNullOrWhiteSpace(
            $env:PSMODULE_YAML_TEST_ARTIFACT
        )) {
        Import-Module -Name $env:PSMODULE_YAML_TEST_ARTIFACT -Force -Global -PassThru |
            Where-Object Name -EQ 'Yaml' |
            Select-Object -First 1
    } else {
        $command = Get-Command -Name ConvertFrom-Yaml -ErrorAction SilentlyContinue
        if ($null -ne $command -and $command.ModuleName -eq 'Yaml') {
            $command.Module
        }
    }
    $artifactManifestPath = if ($null -ne $loadedYamlModule) {
        Join-Path $loadedYamlModule.ModuleBase 'Yaml.psd1'
    } else {
        $null
    }
}

Describe 'Dependency-free package source' {
    It 'contains no external parser assembly, license, or notice payload' {
        @(
            Get-ChildItem -Path (Join-Path $repositoryRoot 'src\assemblies') `
                -File -ErrorAction SilentlyContinue
        ).Count | Should -Be 0
        Test-Path (Join-Path $repositoryRoot 'src\licenses\YamlDotNet.LICENSE.txt') | Should -BeFalse
        Test-Path (Join-Path $repositoryRoot 'src\THIRD-PARTY-NOTICES.txt') | Should -BeFalse
    }

    It 'keeps RequiredAssemblies out of the source manifest' {
        $manifest = Import-PowerShellDataFile -Path (
            Join-Path $repositoryRoot 'src\manifest.psd1'
        )

        $manifest.PowerShellVersion | Should -Be '7.6'
        @($manifest.CompatiblePSEditions) | Should -Be @('Core')
        $manifest.ContainsKey('DotNetFrameworkVersion') | Should -BeFalse
        $manifest.ContainsKey('RequiredAssemblies') | Should -BeFalse
    }

    It 'contains no external parser references or custom assembly loader' {
        $sourceFiles = Get-ChildItem -Path (Join-Path $repositoryRoot 'src') -Recurse -File
        $source = $sourceFiles |
            Where-Object Extension -In @('.ps1', '.psd1', '.psm1') |
            Get-Content -Raw

        $source | Should -Not -Match 'YamlDotNet'
        $source | Should -Not -Match '\bAdd-Type\b'
        $source | Should -Not -Match 'Assembly\]::Load'
    }

    It 'keeps the owned processor layers explicit and source-level' {
        $privatePath = Join-Path $repositoryRoot 'src\functions\private'
        @(
            'New-YamlReaderContext.ps1',
            'Read-YamlDirectiveBlock.ps1',
            'New-YamlSyntaxNode.ps1',
            'ConvertFrom-YamlSyntaxTree.ps1',
            'Resolve-YamlScalar.ps1',
            'ConvertFrom-YamlNode.ps1',
            'Get-YamlSerializationShape.ps1',
            'ConvertTo-YamlNode.ps1',
            'Write-YamlNodeText.ps1'
        ) | ForEach-Object {
            Test-Path -LiteralPath (Join-Path $privatePath $_) |
                Should -BeTrue -Because "$_ defines a required processor layer"
        }
    }

    It 'uses Process-PSModule 6.1.13 and treats tests as important changes' {
        $workflow = Get-Content -Path (
            Join-Path $repositoryRoot '.github\workflows\Process-PSModule.yml'
        ) -Raw

        $workflow | Should -Match 'workflow\.yml@fb1bdb8fefd243292f779d2a856a38db6fe6daf4 # v6\.1\.13'
        $workflow | Should -Match '\^src/'
        $workflow | Should -Match '\^tests/'
    }

    It 'does not skip generated documentation' {
        $configuration = Get-Content -Path (
            Join-Path $repositoryRoot '.github\PSModule.yml'
        ) -Raw

        $configuration | Should -Not -Match '(?ms)Build:\s+Docs:\s+.*Skip:\s*true'
    }

    It 'uses zensical configuration and does not skip site build' {
        $configuration = Get-Content -Path (
            Join-Path $repositoryRoot '.github\PSModule.yml'
        ) -Raw

        $configuration | Should -Not -Match '(?ms)Build:\s+Site:\s+.*Skip:\s*true'
        Test-Path -Path (Join-Path $repositoryRoot '.github\zensical.toml') | Should -BeTrue
        Test-Path -Path (Join-Path $repositoryRoot '.github\mkdocs.yml') | Should -BeFalse
    }
}

Describe 'Generated artifact package' {
    It 'has no RequiredAssemblies or packaged DLL and has a complete FileList' `
        -Skip:$skipArtifactTests {
        $manifest = Import-PowerShellDataFile -Path $artifactManifestPath
        $moduleBase = Split-Path -Parent $artifactManifestPath

        $manifest.PowerShellVersion | Should -Be '7.6'
        @($manifest.CompatiblePSEditions) | Should -Be @('Core')
        $manifest.ContainsKey('RequiredAssemblies') | Should -BeFalse
        $manifest.ContainsKey('DotNetFrameworkVersion') | Should -BeFalse
        @($manifest.FunctionsToExport | Sort-Object) |
            Should -Be @('ConvertFrom-Yaml', 'ConvertTo-Yaml', 'Test-Yaml')
        @($manifest.FileList) | Should -Contain 'Yaml.psm1'
        @($manifest.FileList | Where-Object { $_ -match '\.(?:dll|exe)$' }).Count | Should -Be 0
        @($manifest.FileList | Where-Object { $_ -match 'THIRD-PARTY|YamlDotNet' }).Count | Should -Be 0
        @(Get-ChildItem -Path $moduleBase -Recurse -File -Filter '*.dll').Count | Should -Be 0
        { Test-ModuleManifest -Path $artifactManifestPath } | Should -Not -Throw
    }

    It 'imports in a fresh PowerShell 7 process and preserves arrays, aliases, and depth' `
        -Skip:($skipArtifactTests -or $null -eq (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        $script = @'
$ErrorActionPreference = 'Stop'
$ps = $PSVersionTable.PSVersion
if ($ps.Major -lt 7 -or ($ps.Major -eq 7 -and $ps.Minor -lt 6)) {
    throw "Expected PowerShell 7.6+ but got $ps."
}
Import-Module -Name '__MANIFEST__' -Force
$value = 'v: []' | ConvertFrom-Yaml -AsHashtable
if ($value['v'] -isnot [object[]] -or $value['v'].Count -ne 0) {
    throw 'The empty sequence did not survive import.'
}
if (-not ('name: Ada' | Test-Yaml)) {
    throw 'The imported parser did not validate YAML.'
}
$shared = [ordered]@{ value = 1 }
$roundTrip = [ordered]@{ first = $shared; second = $shared } |
    ConvertTo-Yaml |
    ConvertFrom-Yaml -AsHashtable
if (-not [object]::ReferenceEquals($roundTrip['first'], $roundTrip['second'])) {
   throw 'The fresh-process graph round trip lost alias identity.'
}
$negativeZero = [BitConverter]::Int64BitsToDouble([long]::MinValue)
if ((ConvertTo-Yaml -InputObject $negativeZero).Trim() -ne '-0.0') {
   throw 'The negative-zero sign was lost.'
}
$flow = ('[' * 127) + 'null' + (']' * 127)
if (-not (Test-Yaml -Yaml $flow -Depth 128 -MaxNodes 200)) {
    throw 'The public maximum parse depth failed.'
}
$atLimit = [ordered]@{}
$current = $atLimit
for ($level = 1; $level -lt 127; $level++) {
    $next = [ordered]@{}
    $current['nested'] = $next
    $current = $next
}
$current['value'] = 1
$deepYaml = ConvertTo-Yaml -InputObject $atLimit -Depth 128 -MaxNodes 300
if (-not (Test-Yaml -Yaml $deepYaml -Depth 128 -MaxNodes 300)) {
    throw 'The public maximum serialization depth failed.'
}
'powershell-7-ok'
'@.Replace('__MANIFEST__', $artifactManifestPath.Replace("'", "''"))

        (& pwsh -NoLogo -NoProfile -Command $script) |
            Should -Contain 'powershell-7-ok'
        $LASTEXITCODE | Should -Be 0
    }
}
