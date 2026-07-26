$artifactManifestOverride = $env:PSMODULE_YAML_TEST_ARTIFACT
$yamlModule = $null
if (-not [string]::IsNullOrWhiteSpace($artifactManifestOverride)) {
    $resolvedArtifactManifestPath = (
        Resolve-Path -LiteralPath $artifactManifestOverride -ErrorAction Stop
    ).Path
    $artifactModuleBase = Split-Path -Parent $resolvedArtifactManifestPath
    $yamlModule = Get-Module -Name Yaml |
        Where-Object ModuleBase -EQ $artifactModuleBase |
        Select-Object -First 1
    if ($null -eq $yamlModule) {
        $yamlModule = Import-Module -Name $resolvedArtifactManifestPath -Force -Global -PassThru `
            -ErrorAction Stop |
            Where-Object Name -EQ 'Yaml' |
            Select-Object -First 1
    }
}

if ($null -eq $yamlModule) {
    $yamlModule = Get-Module -Name Yaml | Select-Object -First 1
}

if ($null -eq $yamlModule) {
    throw 'The Yaml module is not loaded. Test-ModuleLocal must import the built module before tests run.'
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

        $document = (Read-YamlStreamCore -Yaml $YamlText -Depth 100 -MaxNodes 100 -MaxAliases 100 `
                -MaxScalarLength 1048576 -MaxTagLength 1024 -MaxTotalTagLength 65536 `
                -MaxNumericLength 4096).Value[0]
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

function Get-TestYamlRepresentationRoot {
    <#
        .SYNOPSIS
        Returns observable metadata from the root representation node.
    #>
    param (
        [Parameter(Mandatory)]
        [string] $Yaml
    )

    $implementation = {
        param ([string] $YamlText)

        $document = (Read-YamlStreamCore -Yaml $YamlText -Depth 100 -MaxNodes 100 -MaxAliases 100 `
                -MaxScalarLength 1048576 -MaxTagLength 1024 -MaxTotalTagLength 65536 `
                -MaxNumericLength 4096).Value[0]
        [pscustomobject]@{
            Kind          = $document.Kind
            Tag           = $document.Tag
            HasUnknownTag = $document.HasUnknownTag
            Value         = $document.Value
        }
    }

    $loadedModule = Get-Module -Name Yaml | Select-Object -First 1
    if ($null -eq $loadedModule) {
        return & $implementation $Yaml
    }
    return & $loadedModule $implementation $Yaml
}
