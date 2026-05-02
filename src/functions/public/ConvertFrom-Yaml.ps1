function ConvertFrom-Yaml {
    <#
        .SYNOPSIS
        Converts a YAML-formatted string to a PowerShell object.

        .DESCRIPTION
        Parses a YAML document and returns a `[PSCustomObject]` (default) or an
        `[ordered]` hashtable when `-AsHashtable` is specified.

        Supports a useful subset of YAML 1.2:
          - Block-style mappings (key: value)
          - Block-style sequences (- item)
          - Nested structures
          - Scalars: strings, integers, floats, booleans, null
          - Single- and double-quoted strings (with `\n`, `\t`, `\r`, `\\`, `\"` in double quotes)
          - YAML frontmatter delimited by `---` (typical in markdown)
          - Full-line comments (`#`) and inline comments after values

        Out of scope for this version: flow style (`[a, b]`, `{a: 1}`), block scalars
        (`|`, `>`), anchors/aliases, tags, multi-document streams, and `!!timestamp`.

        .PARAMETER InputObject
        The YAML content as a string. Accepts pipeline input.

        .PARAMETER AsHashtable
        Returns an `[ordered]` hashtable (`OrderedDictionary`) instead of a `[PSCustomObject]`.

        .PARAMETER NoEnumerate
        When the top-level YAML node is a sequence, prevents PowerShell from unwrapping
        a single-element result into a scalar.

        .PARAMETER Depth
        Maximum nesting depth allowed. Throws when exceeded. Default: 1024.

        .EXAMPLE
        'name: Alice' | ConvertFrom-Yaml

        Returns a PSCustomObject with a `name` property set to `Alice`.

        .EXAMPLE
        Get-Content config.yaml -Raw | ConvertFrom-Yaml -AsHashtable

        Reads a YAML file and returns it as an ordered hashtable.

        .EXAMPLE
        Get-Content post.md -Raw | ConvertFrom-Yaml

        Extracts and parses the YAML frontmatter from a markdown file.

        .OUTPUTS
        System.Management.Automation.PSCustomObject

        .OUTPUTS
        System.Collections.Specialized.OrderedDictionary
    #>
    [Alias('ConvertFrom-Yml')]
    [CmdletBinding()]
    [OutputType([PSCustomObject], [System.Collections.Specialized.OrderedDictionary])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [AllowEmptyString()]
        [string] $InputObject,

        [Parameter()]
        [switch] $AsHashtable,

        [Parameter()]
        [switch] $NoEnumerate,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Depth = 1024
    )

    begin {
        $buffer = [System.Text.StringBuilder]::new()
    }

    process {
        if ($null -ne $InputObject) {
            if ($buffer.Length -gt 0) {
                $null = $buffer.AppendLine()
            }
            $null = $buffer.Append($InputObject)
        }
    }

    end {
        $text = $buffer.ToString()

        if ([string]::IsNullOrWhiteSpace($text)) {
            return $null
        }

        # Strip frontmatter delimiters: leading "---" line and trailing "---" line.
        $text = ConvertFrom-YamlFrontmatter -Text $text

        # Pre-process into logical lines (drop comments and blank lines, keep indentation).
        $lines = ConvertFrom-YamlLineStream -Text $text
        if ($lines.Count -eq 0) {
            return $null
        }

        $context = [pscustomobject]@{
            Lines       = $lines
            Index       = 0
            AsHashtable = [bool] $AsHashtable
            MaxDepth    = $Depth
        }

        $result = ConvertFrom-YamlNode -Context $context -Indent 0 -Depth 0

        if ($NoEnumerate -and $result -is [System.Collections.IList]) {
            return , $result
        }

        return $result
    }
}
