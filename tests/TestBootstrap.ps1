$yamlModule = Get-Module -Name Yaml | Select-Object -First 1
if ($null -eq $yamlModule) {
    $assemblyPath = Join-Path $PSScriptRoot '..\src\assemblies\YamlDotNet.dll'
    [void][System.Reflection.Assembly]::LoadFrom((Resolve-Path $assemblyPath))

    Get-ChildItem -Path (Join-Path $PSScriptRoot '..\src\functions\private') -Filter '*.ps1' |
        Sort-Object Name |
        ForEach-Object { . $_.FullName }

    Get-ChildItem -Path (Join-Path $PSScriptRoot '..\src\functions\public') -Filter '*.ps1' |
        Sort-Object Name |
        ForEach-Object { . $_.FullName }
}

function Get-TestYamlFingerprintLength {
    <#
        .SYNOPSIS
        Returns structural fingerprint lengths for a YAML alias graph.
    #>
    param (
        [Parameter(Mandatory)]
        [string] $Yaml
    )

    $implementation = {
        param ([string] $YamlText)

        $document = @(Read-YamlStreamCore -Yaml $YamlText -Depth 100 -MaxNodes 100 -MaxAliases 100 `
                -MaxScalarLength 1048576)[0]
        $cache = [System.Collections.Generic.Dictionary[int, string]]::new()
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            Test-YamlNodeGraph -Node $document -Visited ([System.Collections.Generic.HashSet[int]]::new()) `
                -FingerprintCache $cache -FingerprintHasher $hasher
        } finally {
            $hasher.Dispose()
        }
        @($cache.Values | ForEach-Object Length)
    }

    $loadedModule = Get-Module -Name Yaml | Select-Object -First 1
    if ($null -eq $loadedModule) {
        return @(& $implementation $Yaml)
    }
    return @(& $loadedModule $implementation $Yaml)
}
