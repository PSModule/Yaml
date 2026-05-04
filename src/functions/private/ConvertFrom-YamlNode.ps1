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
