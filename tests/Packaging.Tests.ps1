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

$importedYamlModule = Get-Module -Name Yaml | Select-Object -First 1
$skipArtifactTests = [string]::IsNullOrWhiteSpace($env:PSMODULE_YAML_TEST_ARTIFACT) -and (
    $null -eq $importedYamlModule
)

BeforeAll {
    . (Join-Path $PSScriptRoot 'TestBootstrap.ps1')
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $loadedYamlModule = $yamlModule
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

    It 'declares the 7.6 Core runtime in the module header' {
        $headerPath = Join-Path $repositoryRoot 'src\header.ps1'
        Test-Path $headerPath | Should -BeTrue

        $header = Get-Content -Path $headerPath -Raw
        $header | Should -Match '#Requires -Version 7\.6'
        $header | Should -Match '#Requires -PSEdition Core'
    }

    It 'keeps the source free of a hand-authored manifest' {
        Test-Path (Join-Path $repositoryRoot 'src\manifest.psd1') | Should -BeFalse
        Test-Path (Join-Path $repositoryRoot 'src\Yaml.psd1') | Should -BeFalse
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
            'Engine\New-YamlReaderContext.ps1',
            'Engine\Read-YamlDirectiveBlock.ps1',
            'Engine\New-YamlSyntaxNode.ps1',
            'Engine\ConvertFrom-YamlSyntaxTree.ps1',
            'Engine\Resolve-YamlScalar.ps1',
            'Conversion\ConvertFrom-YamlNode.ps1',
            'Engine\Get-YamlSerializationShape.ps1',
            'Conversion\ConvertTo-YamlNode.ps1',
            'Streams\ConvertTo-YamlRepresentationNode.ps1',
            'Engine\Write-YamlNodeText.ps1'
        ) | ForEach-Object {
            $isPresent = Test-Path -LiteralPath (Join-Path $privatePath $_)
            $isPresent | Should -BeTrue -Because "$_ defines a required processor layer"
        }
    }

    It 'groups every function file under a domain folder' {
        $functionsPath = Join-Path $repositoryRoot 'src\functions'
        foreach ($scope in @('public', 'private')) {
            $scopePath = Join-Path $functionsPath $scope
            @(Get-ChildItem -LiteralPath $scopePath -File -Filter '*.ps1').Count |
                Should -Be 0 -Because "$scope function files belong in a domain folder"

            foreach ($file in (Get-ChildItem -LiteralPath $scopePath -Recurse -File -Filter '*.ps1')) {
                $relative = [IO.Path]::GetRelativePath($scopePath, $file.FullName)
                ($relative -split '[\\/]').Count |
                    Should -Be 2 -Because "$relative is nested deeper than one domain folder"
            }
        }
    }

    It 'ships a group overview page beside every public domain' {
        $publicPath = Join-Path $repositoryRoot 'src\functions\public'
        $groups = @(Get-ChildItem -LiteralPath $publicPath -Directory)
        $groups.Count | Should -BeGreaterThan 0

        foreach ($group in $groups) {
            $overviewPath = Join-Path $group.FullName "$($group.Name).md"
            Test-Path -LiteralPath $overviewPath |
                Should -BeTrue -Because "$($group.Name) needs a $($group.Name).md section landing page"
        }
    }

    It 'uses Process-PSModule 6.1.15 and treats tests as important changes' {
        $workflow = Get-Content -Path (
            Join-Path $repositoryRoot '.github\workflows\Process-PSModule.yml'
        ) -Raw

        $workflow | Should -Match 'workflow\.yml@688896dc3ef70fb35bd74ae5328e76d5e57fe08a # v6\.1\.15'
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
        @($manifest.CompatiblePSEditions) | Should -Not -Contain 'Desktop'
        $manifest.ContainsKey('RequiredAssemblies') | Should -BeFalse
        $manifest.ContainsKey('DotNetFrameworkVersion') | Should -BeFalse
        @($manifest.FunctionsToExport | Sort-Object) |
            Should -Be @(
                'ConvertFrom-Yaml',
                'ConvertTo-Yaml',
                'Export-Yaml',
                'Format-Yaml',
                'Import-Yaml',
                'Merge-Yaml',
                'Test-Yaml'
            )
        @($manifest.FileList) | Should -Contain 'Yaml.psm1'
        $packagedFiles = @(
            Get-ChildItem -Path $moduleBase -Recurse -File |
                Where-Object FullName -NE $artifactManifestPath |
                ForEach-Object {
                    [System.IO.Path]::GetRelativePath($moduleBase, $_.FullName)
                } |
                Sort-Object
        )
        @($manifest.FileList | Sort-Object) | Should -Be $packagedFiles
        @($manifest.FileList | Where-Object { $_ -match '\.(?:dll|exe)$' }).Count | Should -Be 0
        @($manifest.FileList | Where-Object { $_ -match 'THIRD-PARTY|YamlDotNet' }).Count | Should -Be 0
        @($manifest.PrivateData.PSData.Tags) | Should -Not -Contain 'PSEdition_Desktop'
        @(Get-ChildItem -Path $moduleBase -Recurse -File -Filter '*.dll').Count | Should -Be 0
        { Test-ModuleManifest -Path $artifactManifestPath } | Should -Not -Throw
    }

    It 'imports in a fresh PowerShell 7.6 Core process and preserves arrays, aliases, and depth' `
        -Skip:($skipArtifactTests -or $null -eq (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        $script = @'
$ErrorActionPreference = 'Stop'
$ps = $PSVersionTable.PSVersion
if ($ps -lt [version] '7.6') {
    throw "Expected PowerShell 7.6 or newer but got $ps."
}
if ($PSVersionTable.PSEdition -cne 'Core') {
    throw "Expected PowerShell Core but got $($PSVersionTable.PSEdition)."
}
Import-Module -Name '__MANIFEST__' -Force
$value = 'v: []' | ConvertFrom-Yaml -AsHashtable
if ($value['v'] -isnot [object[]] -or $value['v'].Count -ne 0) {
    throw 'The empty sequence did not survive import.'
}
if (-not ('name: Ada' | Test-Yaml)) {
    throw 'The imported parser did not validate YAML.'
}
$formatted = '{name: Ada, active: true}' | Format-Yaml
if ($formatted -cne "---`n`"name`": `"Ada`"`n`"active`": true") {
    throw 'The imported formatter did not normalize YAML.'
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
"powershell-runtime=$ps;edition=$($PSVersionTable.PSEdition)"
'@.Replace('__MANIFEST__', $artifactManifestPath.Replace("'", "''"))

        $output = @(& pwsh -NoLogo -NoProfile -Command $script)
        $LASTEXITCODE | Should -Be 0
        $runtime = $output | Where-Object { $_ -like 'powershell-runtime=*' } |
            Select-Object -Last 1

        $runtimeMatch = [regex]::Match(
            [string] $runtime,
            '^powershell-runtime=(?<Version>\d+(?:\.\d+){1,3});edition=Core$'
        )
        $runtimeMatch.Success | Should -BeTrue
        ([version] $runtimeMatch.Groups['Version'].Value) -lt [version] '7.6' |
            Should -BeFalse
        Write-Information -MessageData $runtime -InformationAction Continue
    }

    It 'merges complete streams in a fresh PowerShell 7.6 Core process' `
        -Skip:($skipArtifactTests -or $null -eq (Get-Command pwsh -ErrorAction SilentlyContinue)) {
        $script = @'
$ErrorActionPreference = 'Stop'
$ps = $PSVersionTable.PSVersion
if ($ps -lt [version] '7.6') {
    throw "Expected PowerShell 7.6 or newer but got $ps."
}
if ($PSVersionTable.PSEdition -cne 'Core') {
    throw "Expected PowerShell Core but got $($PSVersionTable.PSEdition)."
}
Import-Module -Name '__MANIFEST__' -Force
$merged = Merge-Yaml -InputObject @(
    'service: { image: example:v1, ports: [80] }',
    'service: { image: example:v2, ports: [443] }'
)
if ($merged -match "`r" -or $merged.EndsWith("`n", [System.StringComparison]::Ordinal)) {
    throw 'The imported merge command did not normalize its output contract.'
}
$mergedValue = $merged | ConvertFrom-Yaml -AsHashtable
if ($mergedValue['service']['image'] -cne 'example:v2' -or
    $mergedValue['service']['ports'][0] -ne 443) {
    throw 'The imported merge command did not apply later stream precedence.'
}
"merge-runtime=$ps;edition=$($PSVersionTable.PSEdition)"
'@.Replace('__MANIFEST__', $artifactManifestPath.Replace("'", "''"))

        $output = @(& pwsh -NoLogo -NoProfile -Command $script)
        $LASTEXITCODE | Should -Be 0
        $runtime = $output | Where-Object { $_ -like 'merge-runtime=*' } |
            Select-Object -Last 1

        $runtimeMatch = [regex]::Match(
            [string] $runtime,
            '^merge-runtime=(?<Version>\d+(?:\.\d+){1,3});edition=Core$'
        )
        $runtimeMatch.Success | Should -BeTrue
        ([version] $runtimeMatch.Groups['Version'].Value) -lt [version] '7.6' |
            Should -BeFalse
        Write-Information -MessageData $runtime -InformationAction Continue
    }
}
