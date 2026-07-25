<#
    .SYNOPSIS
    Demonstrates the public Yaml commands.
#>

Import-Module -Name Yaml

$yaml = @'
---
name: example
enabled: true
ports: [80, 443]
'@

# Parse a mapping to an ordered PSCustomObject.
$config = $yaml | ConvertFrom-Yaml
$config

# Keep a top-level sequence as one pipeline record.
$servers = @'
- name: web-1
- name: web-2
'@ | ConvertFrom-Yaml -NoEnumerate
$servers.Count

# Preserve mappings whose keys cannot be PowerShell property names.
$complexMapping = @'
? [region, port]
: eu-1
'@ | ConvertFrom-Yaml -AsHashtable
$complexMapping

# Serialize supported PowerShell data and parse it again.
$outputYaml = [ordered]@{
    name    = 'example'
    enabled = $true
    ports   = @(80, 443)
} | ConvertTo-Yaml -ExplicitDocumentStart

$outputYaml
$outputYaml | ConvertFrom-Yaml

# Atomically export one file, then import it with strict decoding.
$configPath = Join-Path $env:TEMP 'yaml-example.yaml'
$config | Export-Yaml -Path $configPath -PassThru
$importedConfig = Import-Yaml -LiteralPath $configPath
$importedConfig
Remove-Item -LiteralPath $configPath

# Test syntax, duplicate keys, tags, and resource limits without conversion.
$isValid = $outputYaml | Test-Yaml
$isValid
