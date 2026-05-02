function ConvertTo-YamlNode {
    <#
        .SYNOPSIS
        Recursively writes a value as a YAML block-style node into the supplied StringBuilder.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [System.Text.StringBuilder] $Builder,

        [Parameter(Mandatory)]
        [int] $Level,

        [Parameter(Mandatory)]
        [int] $CurrentDepth,

        [Parameter(Mandatory)]
        [pscustomobject] $Options
    )

    if ($CurrentDepth -gt $Options.Depth) {
        $repr = if ($null -eq $Value) { 'null' } else { Format-YamlScalar -Value $Value.ToString() -Options $Options }
        $null = $Builder.Append($repr).AppendLine()
        return
    }

    if ($null -eq $Value) {
        $null = $Builder.Append('null').AppendLine()
        return
    }

    # Unwrap PSObject for type tests.
    $raw = if ($Value -is [psobject] -and $null -ne $Value.PSObject -and $null -ne $Value.PSObject.BaseObject) {
        $Value.PSObject.BaseObject
    } else {
        $Value
    }

    if (Test-YamlMappingType -Value $raw) {
        ConvertTo-YamlMapping -Value $Value -Builder $Builder -Level $Level -CurrentDepth $CurrentDepth -Options $Options
        return
    }

    if (Test-YamlSequenceType -Value $raw) {
        ConvertTo-YamlSequence -Value $raw -Builder $Builder -Level $Level -CurrentDepth $CurrentDepth -Options $Options
        return
    }

    # Scalar.
    $scalar = Format-YamlScalar -Value $raw -Options $Options
    $null = $Builder.Append($scalar).AppendLine()
}
