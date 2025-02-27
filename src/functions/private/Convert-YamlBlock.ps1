function Convert-YamlBlock {
    <#

    #>
    param (

        [string[]]$Lines,

        [int]$StartIndex,

        [int] $IndentLevel
    )

    $i = $StartIndex
    # Skip leading empty lines
    while ($i -lt $Lines.Count -and $Lines[$i].Trim() -eq '') {
        $i++
    }

    # If we've reached the end, return an empty hashtable
    if ($i -ge $Lines.Count) {
        return @{
            object     = @{}
            next_index = $i
        }
    }

    $firstLine = $Lines[$i].Trim()

    # Check if this block is a sequence (starts with "-")
    if ($firstLine -like '-*') {
        $array = @()
        while ($i -lt $Lines.Count) {
            $line = $Lines[$i]
            if ($line.Trim() -eq '') {
                $i++
                continue
            }
            $currentIndent = Get-YamlIndentLevel -Line $line
            if ($currentIndent -lt $IndentLevel) {
                break
            }
            if ($currentIndent -gt $IndentLevel) {
                throw "Unexpected indentation at line $($i + 1)"
            }
            $content = $line.Trim()
            if ($content -like '-*') {
                if ($content -eq '-') {
                    # Sequence item is a nested block
                    $subBlock = Convert-YamlBlock -Lines $Lines -StartIndex ($i + 1) -IndentLevel ($IndentLevel + 1)
                    if ($subBlock.next_index -eq $i + 1) {
                        $array += $null
                    } else {
                        $array += $subBlock.object
                    }
                    $i = $subBlock.next_index
                } else {
                    # Sequence item is a scalar
                    $rawValue = $content.Substring(1)
                    $value = Convert-YamlValue -RawValue $rawValue
                    $array += $value
                    $i++
                }
            } else {
                throw "Expected '-' for sequence item at line $($i + 1)"
            }
        }
        return @{
            object     = $array
            next_index = $i
        }
    } else {
        # This block is a mapping
        $hashtable = @{}
        while ($i -lt $Lines.Count) {
            $line = $Lines[$i]
            if ($line.Trim() -eq '') {
                $i++
                continue
            }
            $currentIndent = Get-YamlIndentLevel -Line $line
            if ($currentIndent -lt $IndentLevel) {
                break
            }
            if ($currentIndent -gt $IndentLevel) {
                throw "Unexpected indentation at line $($i + 1)"
            }
            $content = $line.Trim()
            if ($content -match '^(.*):$') {
                # Key with a nested block
                $key = $matches[1].Trim()
                $subBlock = Convert-YamlBlock -Lines $Lines -StartIndex ($i + 1) -IndentLevel ($IndentLevel + 1)
                if ($subBlock.next_index -eq $i + 1) {
                    $hashtable[$key] = $null
                } else {
                    $hashtable[$key] = $subBlock.object
                }
                $i = $subBlock.next_index
            } elseif ($content -match '^(.*):\s*(.*)$') {
                # Key-value pair
                $key = $matches[1].Trim()
                $rawValue = $matches[2]
                $value = Convert-YamlValue -RawValue $rawValue
                $hashtable[$key] = $value
                $i++
            } else {
                throw "Invalid YAML syntax at line $($i + 1)"
            }
        }
        return @{
            object     = $hashtable
            next_index = $i
        }
    }
}
