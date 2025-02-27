function Convert-YamlBlock {
    <#
        .SYNOPSIS
        Converts a block of YAML text into a PowerShell object.

        .DESCRIPTION
        This function processes a block of YAML lines and converts it into a corresponding PowerShell object.
        It determines whether the block is a sequence or a mapping and parses it accordingly. If the block
        represents a sequence (starting with '-'), it returns an array. If it represents a mapping, it returns
        a hashtable. Unexpected indentation or invalid YAML syntax will result in an error.

        .EXAMPLE
        Convert-YamlBlock -Lines @("key: value") -StartIndex 0 -IndentLevel 0

        Output:
        ```powershell
        object     : @{key=value}
        next_index : 1
        ```

        Parses a simple key-value pair YAML block and returns a hashtable.

        .EXAMPLE
        Convert-YamlBlock -Lines @("- item1", "- item2") -StartIndex 0 -IndentLevel 0

        Output:
        ```powershell
        object     : @("item1", "item2")
        next_index : 2
        ```

        Parses a YAML sequence into a PowerShell array.

        .OUTPUTS
        hashtable. Returns a hashtable if the YAML block represents a mapping.

        array. Returns an array if the YAML block represents a sequence.

        .LINK
        https://psmodule.io/Yaml/Functions/Convert-YamlBlock/
    #>
    [OutputType([hashtable])]
    [CmdletBinding()]
    param (
        # An array of YAML lines to process.
        [Parameter(Mandatory)]
        [string[]] $Lines,

        # The starting index in the array from which parsing should begin.
        [Parameter(Mandatory)]
        [int] $StartIndex,

        # The indentation level to be considered while parsing the YAML block.
        [Parameter(Mandatory)]
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
