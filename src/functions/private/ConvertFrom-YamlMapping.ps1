function ConvertFrom-YamlMapping {
    <#
        .SYNOPSIS
        Parses a YAML block-style mapping into a PSCustomObject or OrderedDictionary.
    #>
    [CmdletBinding()]
    [OutputType([System.Collections.Specialized.OrderedDictionary], [pscustomobject])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [Parameter(Mandatory)] [int] $Indent,
        [Parameter(Mandatory)] [int] $Depth
    )

    $lines = $Context.Lines
    $map = [ordered]@{}

    while ($Context.Index -lt $lines.Count) {
        $line = $lines[$Context.Index]
        if ($line.Indent -lt $Indent) { break }
        if ($line.Indent -gt $Indent) {
            throw "ConvertFrom-Yaml: unexpected indentation at line $($line.Number)."
        }
        if ($line.Content.StartsWith('- ') -or $line.Content -eq '-') {
            # A sequence at the same indent as a mapping key is a sibling, not part of mapping.
            break
        }

        $colonIdx = Find-YamlMappingColon -Content $line.Content
        if ($colonIdx -lt 0) {
            throw "ConvertFrom-Yaml: expected mapping key at line $($line.Number): '$($line.Content)'."
        }

        $key = ConvertFrom-YamlScalar -Raw $line.Content.Substring(0, $colonIdx).Trim()
        $rest = $line.Content.Substring($colonIdx + 1).Trim()

        $Context.Index++

        if ($rest.Length -gt 0) {
            $map[[string]$key] = ConvertFrom-YamlScalar -Raw $rest
            continue
        }

        # Value on subsequent indented lines (mapping or sequence) or null.
        if ($Context.Index -ge $lines.Count) {
            $map[[string]$key] = $null
            continue
        }

        $next = $lines[$Context.Index]
        if ($next.Indent -le $Indent) {
            $map[[string]$key] = $null
            continue
        }

        # Sequences are allowed to start at the same indent as the parent key in YAML.
        # We require the child to be indented strictly greater than the key here for clarity.
        $childIndent = $next.Indent
        $value = ConvertFrom-YamlNode -Context $Context -Indent $childIndent -Depth ($Depth + 1)
        $map[[string]$key] = $value
    }

    if ($Context.AsHashtable) {
        return $map
    }

    $obj = [pscustomobject]@{}
    foreach ($k in $map.Keys) {
        Add-Member -InputObject $obj -MemberType NoteProperty -Name $k -Value $map[$k]
    }
    return $obj
}
