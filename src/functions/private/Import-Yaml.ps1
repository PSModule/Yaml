function Import-Yaml {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $yamlContent = Get-Content -Path $Path -Raw
    return ConvertFrom-Yaml -Yaml $yamlContent
}
