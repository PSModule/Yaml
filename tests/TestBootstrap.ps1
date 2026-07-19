$assemblyPath = Join-Path $PSScriptRoot '..\src\assemblies\YamlDotNet.dll'
[void][System.Reflection.Assembly]::LoadFrom((Resolve-Path $assemblyPath))

Get-ChildItem -Path (Join-Path $PSScriptRoot '..\src\functions\private') -Filter '*.ps1' |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }

Get-ChildItem -Path (Join-Path $PSScriptRoot '..\src\functions\public') -Filter '*.ps1' |
    Sort-Object Name |
    ForEach-Object { . $_.FullName }
