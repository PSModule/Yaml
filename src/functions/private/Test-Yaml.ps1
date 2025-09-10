function Test-Yaml {
    param (
        [Parameter(Mandatory = $true)]
        [string]$Yaml,
        [string]$SchemaPath
    )

    try {
        # Attempt to parse the YAML
        $object = ConvertFrom-Yaml -Yaml $Yaml

        # If no schema is provided, syntax is valid
        if (-not $SchemaPath) {
            return $true
        } else {
            # Load the schema and validate
            $schema = Get-Content -Path $SchemaPath -Raw | ConvertFrom-Json
            return Test-Schema -Object $object -Schema $schema
        }
    } catch {
        Write-Error "YAML syntax error: $_"
        return $false
    }
}
