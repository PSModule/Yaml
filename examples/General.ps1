<#
    .SYNOPSIS
    Example usage of the Yaml module: parse YAML to objects and convert objects back to YAML.
#>

Import-Module -Name 'Yaml'

# 1. Parse a YAML string into a PSCustomObject
$yaml = @'
name: Alice
age: 30
skills:
  - PowerShell
  - YAML
'@

$person = $yaml | ConvertFrom-Yaml
$person.name        # Alice
$person.skills[0]   # PowerShell

# 2. Parse YAML as an ordered hashtable
$hash = $yaml | ConvertFrom-Yaml -AsHashtable
$hash['age']        # 30

# 3. Parse YAML frontmatter from a markdown document
$markdown = @'
---
title: Hello world
draft: false
---
# Body

Markdown content here.
'@

$frontmatter = $markdown | ConvertFrom-Yaml
$frontmatter.title  # Hello world

# 4. Convert an object to YAML
[ordered]@{
    name   = 'Alice'
    age    = 30
    skills = @('PowerShell', 'YAML')
} | ConvertTo-Yaml

# 5. Force a top-level sequence with -AsArray
Get-Process | Select-Object -First 3 Name, Id | ConvertTo-Yaml -AsArray

# 6. Round-trip
$obj = [ordered]@{ a = 1; b = @('x', 'y') }
$obj | ConvertTo-Yaml | ConvertFrom-Yaml -AsHashtable
