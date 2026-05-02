function ConvertTo-YamlMapping {
    <#
        .SYNOPSIS
        Writes a mapping value as a YAML block-style mapping into the StringBuilder.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Value,
        [Parameter(Mandatory)] [System.Text.StringBuilder] $Builder,
        [Parameter(Mandatory)] [int] $Level,
        [Parameter(Mandatory)] [int] $CurrentDepth,
        [Parameter(Mandatory)] [pscustomobject] $Options
    )

    $pairs = Get-YamlMappingPair -Value $Value
    if ($pairs.Count -eq 0) {
        $null = $Builder.Append('{}').AppendLine()
        return
    }

    $indent = ' ' * ($Level * $Options.Indent)
    foreach ($pair in $pairs) {
        $keyText = Format-YamlKey -Key $pair.Key
        $val = $pair.Value
        $null = $Builder.Append($indent).Append($keyText).Append(':')

        if ($null -eq $val) {
            $null = $Builder.Append(' null').AppendLine()
            continue
        }

        $rawVal = if ($val -is [psobject] -and $null -ne $val.PSObject -and $null -ne $val.PSObject.BaseObject) {
            $val.PSObject.BaseObject
        } else {
            $val
        }

        if (Test-YamlMappingType -Value $rawVal) {
            $childPairs = Get-YamlMappingPair -Value $val
            if ($childPairs.Count -eq 0) {
                $null = $Builder.Append(' {}').AppendLine()
            } else {
                $null = $Builder.AppendLine()
                ConvertTo-YamlNode -Value $val -Builder $Builder -Level ($Level + 1) -CurrentDepth ($CurrentDepth + 1) -Options $Options
            }
            continue
        }

        if (Test-YamlSequenceType -Value $rawVal) {
            $arr = @($rawVal)
            if ($arr.Count -eq 0) {
                $null = $Builder.Append(' []').AppendLine()
            } else {
                $null = $Builder.AppendLine()
                ConvertTo-YamlSequence -Value $rawVal -Builder $Builder -Level ($Level + 1) -CurrentDepth ($CurrentDepth + 1) -Options $Options
            }
            continue
        }

        $scalar = Format-YamlScalar -Value $rawVal -Options $Options
        $null = $Builder.Append(' ').Append($scalar).AppendLine()
    }
}
