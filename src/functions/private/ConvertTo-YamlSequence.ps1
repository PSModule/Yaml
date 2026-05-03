function ConvertTo-YamlSequence {
    <#
        .SYNOPSIS
        Writes a sequence value as a YAML block-style sequence into the StringBuilder.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [object] $Value,
        [Parameter(Mandatory)] [System.Text.StringBuilder] $Builder,
        [Parameter(Mandatory)] [int] $Level,
        [Parameter(Mandatory)] [int] $CurrentDepth,
        [Parameter(Mandatory)] [pscustomobject] $Options
    )

    $items = @($Value)
    if ($items.Count -eq 0) {
        $indent = ' ' * ($Level * $Options.Indent)
        $null = $Builder.Append($indent).Append('[]').AppendLine()
        return
    }

    $indent = ' ' * ($Level * $Options.Indent)

    foreach ($item in $items) {
        if ($item -is [psobject] -and $null -ne $item.PSObject -and $null -ne $item.PSObject.BaseObject) {
            $rawItem = $item.PSObject.BaseObject
        } else {
            $rawItem = $item
        }

        if ($null -eq $item) {
            $null = $Builder.Append($indent).Append('- null').AppendLine()
            continue
        }

        if (Test-YamlMappingType -Value $rawItem) {
            $pairs = Get-YamlMappingPair -Value $item
            if ($pairs.Count -eq 0) {
                $null = $Builder.Append($indent).Append('- {}').AppendLine()
                continue
            }
            $first = $true
            $childIndent = ' ' * (($Level + 1) * $Options.Indent)
            foreach ($pair in $pairs) {
                $keyText = Format-YamlKey -Key $pair.Key
                $prefix = if ($first) { "$indent- " } else { $childIndent }
                $first = $false

                $val = $pair.Value
                if ($val -is [psobject] -and $null -ne $val.PSObject -and $null -ne $val.PSObject.BaseObject) {
                    $rawVal = $val.PSObject.BaseObject
                } else {
                    $rawVal = $val
                }

                if ($null -eq $val) {
                    $null = $Builder.Append($prefix).Append($keyText).Append(': null').AppendLine()
                    continue
                }

                if (Test-YamlMappingType -Value $rawVal) {
                    $childPairs = Get-YamlMappingPair -Value $val
                    if ($childPairs.Count -eq 0) {
                        $null = $Builder.Append($prefix).Append($keyText).Append(': {}').AppendLine()
                    } else {
                        $null = $Builder.Append($prefix).Append($keyText).Append(':').AppendLine()
                        ConvertTo-YamlNode -Value $val -Builder $Builder -Level ($Level + 2) -CurrentDepth ($CurrentDepth + 1) -Options $Options
                    }
                    continue
                }

                if (Test-YamlSequenceType -Value $rawVal) {
                    $arr = @($rawVal)
                    if ($arr.Count -eq 0) {
                        $null = $Builder.Append($prefix).Append($keyText).Append(': []').AppendLine()
                    } else {
                        $null = $Builder.Append($prefix).Append($keyText).Append(':').AppendLine()
                        ConvertTo-YamlSequence -Value $rawVal -Builder $Builder -Level ($Level + 2) -CurrentDepth ($CurrentDepth + 1) -Options $Options
                    }
                    continue
                }

                $scalar = Format-YamlScalar -Value $rawVal -Options $Options
                $null = $Builder.Append($prefix).Append($keyText).Append(': ').Append($scalar).AppendLine()
            }
            continue
        }

        if (Test-YamlSequenceType -Value $rawItem) {
            $arr = @($rawItem)
            if ($arr.Count -eq 0) {
                $null = $Builder.Append($indent).Append('- []').AppendLine()
            } else {
                $null = $Builder.Append($indent).Append('-').AppendLine()
                ConvertTo-YamlSequence -Value $rawItem -Builder $Builder -Level ($Level + 1) -CurrentDepth ($CurrentDepth + 1) -Options $Options
            }
            continue
        }

        $scalar = Format-YamlScalar -Value $rawItem -Options $Options
        $null = $Builder.Append($indent).Append('- ').Append($scalar).AppendLine()
    }
}
