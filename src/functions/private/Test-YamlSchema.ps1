

# Helper function for basic schema validation
function Test-YamlSchema {
    param (
        $Object,
        $Schema
    )

    if ($Schema.type -eq 'object') {
        foreach ($prop in $Schema.properties.PSObject.Properties) {
            $propName = $prop.Name
            $propSchema = $prop.Value

            # Check for required properties
            if ($propSchema.required -and -not $Object.PSObject.Properties[$propName]) {
                Write-Error "Missing required property: $propName"
                return $false
            }

            # Check property types if present
            if ($Object.PSObject.Properties[$propName]) {
                $value = $Object.$propName
                if ($propSchema.type -eq 'string' -and $value -isnot [string]) {
                    Write-Error "Property $propName should be a string"
                    return $false
                } elseif ($propSchema.type -eq 'integer' -and $value -isnot [int]) {
                    Write-Error "Property $propName should be an integer"
                    return $false
                }
            }
        }
        return $true
    } else {
        Write-Error "Schema validation only supports 'object' type at root"
        return $false
    }
}
