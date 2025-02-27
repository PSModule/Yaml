# Function to convert PSCustomObject to YAML string
function ConvertTo-Yaml {
    param (
        [Parameter(Mandatory = $true)]
        $Object,
        [int]$IndentLevel = 0
    )

    $indent = ' ' * ($IndentLevel * 2)

    if ($Object -is [PSCustomObject]) {
        $lines = @()
        foreach ($property in $Object.PSObject.Properties) {
            $key = $property.Name
            $value = $property.Value
            if ($value -is [PSCustomObject] -or $value -is [array]) {
                $lines += "$indent$key`:"
                $lines += ConvertTo-Yaml -Object $value -IndentLevel ($IndentLevel + 1)
            } else {
                # Handle scalar values
                if ($value -is [string]) {
                    $yamlValue = '"' + $value.Replace('"', '\"') + '"'
                } elseif ($value -is [int] -or $value -is [double]) {
                    $yamlValue = $value.ToString()
                } elseif ($value -is [bool]) {
                    $yamlValue = if ($value) { 'true' } else { 'false' }
                } elseif ($null -eq $value) {
                    $yamlValue = 'null'
                } else {
                    $yamlValue = $value.ToString()
                }
                $lines += "$indent$key`: $yamlValue"
            }
        }
        return $lines -join "`n"
    } elseif ($Object -is [array]) {
        $lines = @()
        foreach ($item in $Object) {
            if ($item -is [PSCustomObject] -or $item -is [array]) {
                $lines += "$indent- "
                $subLines = ConvertTo-Yaml -Object $item -IndentLevel ($IndentLevel + 1)
                $lines += $subLines
            } else {
                # Handle scalar values
                if ($item -is [string]) {
                    $yamlItem = '"' + $item.Replace('"', '\"') + '"'
                } elseif ($item -is [int] -or $item -is [double]) {
                    $yamlItem = $item.ToString()
                } elseif ($item -is [bool]) {
                    $yamlItem = if ($item) { 'true' } else { 'false' }
                } elseif ($null -eq $value) {
                    $yamlItem = 'null'
                } else {
                    $yamlItem = $item.ToString()
                }
                $lines += "$indent- $yamlItem"
            }
        }
        return $lines -join "`n"
    } else {
        # Scalar value (though typically not reached)
        return "$indent$Object"
    }
}
