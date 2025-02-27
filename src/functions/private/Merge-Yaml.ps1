function Merge-Yaml {
    param (
        [Parameter(Mandatory = $true)]
        [string]$BaseYaml,
        [Parameter(Mandatory = $true)]
        [string[]]$YamlArray
    )

    # Parse the base YAML
    $baseObject = ConvertFrom-Yaml -Yaml $BaseYaml

    # Merge each YAML in the array
    foreach ($yaml in $YamlArray) {
        $overrideObject = ConvertFrom-Yaml -Yaml $yaml
        $baseObject = Merge-YamlObjects -Base $baseObject -Override $overrideObject
    }

    # Convert back to YAML
    return ConvertTo-Yaml -Object $baseObject
}
