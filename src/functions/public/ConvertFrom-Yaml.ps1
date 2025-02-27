# Function to convert YAML string to PSCustomObject
function ConvertFrom-Yaml {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Yaml
    )
    $lines = $Yaml -split "`n"
    $parsed = Convert-YamlBlock -Lines $lines -StartIndex 0 -IndentLevel 0
    $rootObject = $parsed.object
    return ConvertTo-YamlPSCustomObject -Object $rootObject
}
