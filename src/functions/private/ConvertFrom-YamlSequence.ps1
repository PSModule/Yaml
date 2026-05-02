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
