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

Describe 'Packaged dependency' {
    BeforeAll {
        $repositoryRoot = Split-Path -Parent $PSScriptRoot
    }

    It 'bundles the exact YamlDotNet 18.1.0 netstandard2.0 assembly' {
        $hash = Get-FileHash -Path (
            Join-Path $repositoryRoot 'src\assemblies\YamlDotNet.dll'
        ) -Algorithm SHA256

        $hash.Hash | Should -Be '91CD6D1FD0AE5B64BF6B252EB3B1AF2382CBC599C29045427C45FE8403D4295D'
    }

    It 'keeps RequiredAssemblies out of the source manifest' {
        $manifest = Import-PowerShellDataFile -Path (
            Join-Path $repositoryRoot 'src\manifest.psd1'
        )

        $manifest.DotNetFrameworkVersion | Should -Be '4.7.2'
        $manifest.ContainsKey('RequiredAssemblies') | Should -BeFalse
    }

    It 'packages the upstream license and dependency provenance' {
        $license = Get-Content -Path (
            Join-Path $repositoryRoot 'src\licenses\YamlDotNet.LICENSE.txt'
        ) -Raw
        $notice = Get-Content -Path (
            Join-Path $repositoryRoot 'src\THIRD-PARTY-NOTICES.txt'
        ) -Raw

        $license | Should -Match 'Copyright \(c\) 2008, 2009, 2010'
        $license | Should -Match 'Permission is hereby granted, free of charge'
        $notice | Should -Match 'YamlDotNet 18\.1\.0'
        $notice | Should -Match 'lib/netstandard2\.0/YamlDotNet\.dll'
        $notice | Should -Match '59FFE65ADE67AD9D886267F877B634A450363CB81B94E19DB9CA4C36461416F6'
        $notice | Should -Match '91CD6D1FD0AE5B64BF6B252EB3B1AF2382CBC599C29045427C45FE8403D4295D'
    }

    It 'uses Process-PSModule 6.1.4 and treats tests as important changes' {
        $workflow = Get-Content -Path (
            Join-Path $repositoryRoot '.github\workflows\Process-PSModule.yml'
        ) -Raw

        $workflow | Should -Match 'workflow\.yml@da180bac16b13bfbcdf08b2e4e221b5b49e5ff28 # v6\.1\.4'
        $workflow | Should -Match '\^src/'
        $workflow | Should -Match '\^tests/'
    }

    It 'does not add a custom assembly loader to module source' {
        $source = Get-ChildItem -Path (Join-Path $repositoryRoot 'src') -Recurse -File |
            Where-Object Extension -EQ '.ps1' |
            Get-Content -Raw

        $source | Should -Not -Match '\bAdd-Type\b'
        $source | Should -Not -Match 'Assembly\]::Load'
    }
}
