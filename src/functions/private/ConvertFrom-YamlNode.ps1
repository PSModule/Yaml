function ConvertFrom-YamlNode {
    <#
        .SYNOPSIS
        Recursive-descent parser for the YAML line stream produced by ConvertFrom-YamlLineStream.

        .DESCRIPTION
        Reads a node starting at the current line index and at the given indentation level.
        Returns either a mapping (PSCustomObject or OrderedDictionary), a sequence (array),
        or a scalar.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [int] $Indent,

        [Parameter(Mandatory)]
        [int] $Depth
    )

    if ($Depth -gt $Context.MaxDepth) {
        throw "ConvertFrom-Yaml: maximum nesting depth ($($Context.MaxDepth)) exceeded."
    }

    $lines = $Context.Lines
    if ($Context.Index -ge $lines.Count) {
        return $null
    }

    $current = $lines[$Context.Index]

    # Determine node kind from the first line at this indent.
    if ($current.Content.StartsWith('- ') -or $current.Content -eq '-') {
        return ConvertFrom-YamlSequence -Context $Context -Indent $Indent -Depth $Depth
    }

    return ConvertFrom-YamlMapping -Context $Context -Indent $Indent -Depth $Depth
}

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

function ConvertFrom-YamlSequence {
    <#
        .SYNOPSIS
        Parses a YAML block-style sequence into a PowerShell array.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseOutputTypeCorrectly', '',
        Justification = 'Comma-unary operator preserves array type; PSScriptAnalyzer misdetects as Object[].')]
    [CmdletBinding()]
    [OutputType([object[]])]
    param(
        [Parameter(Mandatory)] [pscustomobject] $Context,
        [Parameter(Mandatory)] [int] $Indent,
        [Parameter(Mandatory)] [int] $Depth
    )

    $lines = $Context.Lines
    $list = [System.Collections.Generic.List[object]]::new()

    while ($Context.Index -lt $lines.Count) {
        $line = $lines[$Context.Index]
        if ($line.Indent -lt $Indent) { break }
        if ($line.Indent -gt $Indent) {
            throw "ConvertFrom-Yaml: unexpected indentation at line $($line.Number)."
        }
        if (-not ($line.Content.StartsWith('- ') -or $line.Content -eq '-')) {
            break
        }

        $afterDash = if ($line.Content.Length -ge 2) { $line.Content.Substring(2).TrimEnd() } else { '' }

        if ($afterDash.Length -eq 0) {
            # Value on subsequent indented lines.
            $Context.Index++
            if ($Context.Index -ge $lines.Count) {
                $list.Add($null)
                continue
            }
            $next = $lines[$Context.Index]
            if ($next.Indent -le $Indent) {
                $list.Add($null)
                continue
            }
            $list.Add((ConvertFrom-YamlNode -Context $Context -Indent $next.Indent -Depth ($Depth + 1)))
            continue
        }

        # Inline element: could be a scalar, or a mapping like "- key: value" with possibly more
        # mapping keys on following lines indented at "Indent + 2" (under the dash).
        $colonIdx = Find-YamlMappingColon -Content $afterDash
        if ($colonIdx -ge 0) {
            # Treat this as a single-line entry into a mapping. Build a synthetic line stream:
            # the current "key: value" line gets re-interpreted at indent (Indent + 2), and any
            # continuation lines at indent > (Indent + 2) belong to the same mapping.
            $childIndent = $Indent + 2
            $synthetic = [pscustomobject]@{
                Indent  = $childIndent
                Content = $afterDash
                Number  = $line.Number
            }
            # Replace current line with synthetic and recurse as a mapping.
            $Context.Lines[$Context.Index] = $synthetic
            $value = ConvertFrom-YamlMapping -Context $Context -Indent $childIndent -Depth ($Depth + 1)
            $list.Add($value)
            continue
        }

        # Plain scalar element.
        $list.Add((ConvertFrom-YamlScalar -Raw $afterDash))
        $Context.Index++
    }

    return , $list.ToArray()
}

function Find-YamlMappingColon {
    <#
        .SYNOPSIS
        Returns the index of the unquoted `:` separator in a content line, or -1 if not found.

        .DESCRIPTION
        The colon must be followed by whitespace or end-of-line for it to be a YAML mapping
        separator. Colons inside quoted strings are ignored.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Content
    )

    $inSingle = $false
    $inDouble = $false
    for ($i = 0; $i -lt $Content.Length; $i++) {
        $c = $Content[$i]
        if ($c -eq '\' -and $inDouble) { $i++; continue }
        if ($c -eq "'" -and -not $inDouble) { $inSingle = -not $inSingle; continue }
        if ($c -eq '"' -and -not $inSingle) { $inDouble = -not $inDouble; continue }
        if ($c -eq ':' -and -not $inSingle -and -not $inDouble) {
            if ($i -eq $Content.Length - 1) { return $i }
            $next = $Content[$i + 1]
            if ($next -eq ' ' -or $next -eq "`t") { return $i }
        }
    }
    return -1
}

function ConvertFrom-YamlScalar {
    <#
        .SYNOPSIS
        Converts a raw YAML scalar token into the appropriate PowerShell type.
    #>
    [CmdletBinding()]
    [OutputType([string], [bool], [int], [long], [double])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Raw
    )

    $value = $Raw.Trim()

    if ($value.Length -eq 0) { return $null }

    # Quoted strings.
    if ($value.Length -ge 2 -and $value.StartsWith("'") -and $value.EndsWith("'")) {
        $inner = $value.Substring(1, $value.Length - 2)
        return ($inner -replace "''", "'")
    }
    if ($value.Length -ge 2 -and $value.StartsWith('"') -and $value.EndsWith('"')) {
        $inner = $value.Substring(1, $value.Length - 2)
        return (Expand-YamlDoubleQuoted -Text $inner)
    }

    # Null literal (YAML 1.2.2 core schema): empty, ~, null only. Case-sensitive.
    if ($value -ceq '~' -or $value -ceq 'null') { return $null }

    # Boolean literal (YAML 1.2.2 core schema): true / false only. Case-sensitive.
    if ($value -ceq 'true') { return $true }
    if ($value -ceq 'false') { return $false }

    # Integer.
    $intVal = 0
    if ([int]::TryParse($value, [System.Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref] $intVal)) {
        return $intVal
    }
    $longVal = [long]0
    if ([long]::TryParse($value, [System.Globalization.NumberStyles]::Integer, [cultureinfo]::InvariantCulture, [ref] $longVal)) {
        return $longVal
    }

    # Float.
    $dblVal = 0.0
    if ([double]::TryParse($value, [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref] $dblVal)) {
        return $dblVal
    }

    # Plain string.
    return $value
}

function Expand-YamlDoubleQuoted {
    <#
        .SYNOPSIS
        Expands escape sequences inside a double-quoted YAML scalar.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text
    )

    $sb = [System.Text.StringBuilder]::new()
    $i = 0
    while ($i -lt $Text.Length) {
        $c = $Text[$i]
        if ($c -eq '\' -and $i + 1 -lt $Text.Length) {
            $next = $Text[$i + 1]
            $expanded = $true
            switch ($next) {
                'n' { $null = $sb.Append("`n") }
                't' { $null = $sb.Append("`t") }
                'r' { $null = $sb.Append("`r") }
                '"' { $null = $sb.Append('"') }
                '\' { $null = $sb.Append('\') }
                '0' { $null = $sb.Append([char]0) }
                default { $expanded = $false }
            }

            if ($expanded) {
                $i += 2
                continue
            }
        }
        $null = $sb.Append($c)
        $i++
    }
    return $sb.ToString()
}
