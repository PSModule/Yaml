function ConvertTo-Yaml {
    <#
        .SYNOPSIS
        Converts a PowerShell object to a YAML-formatted string.

        .DESCRIPTION
        Serializes objects, hashtables/dictionaries, and arrays to a block-style YAML
        string. Mirrors the parameter shape of `ConvertTo-Json` where applicable.

        Out of scope for this version: flow style (`[a, b]`, `{a: 1}`), block scalars
        (`|`, `>`), anchors/aliases, tags, and timestamp formatting.

        .PARAMETER InputObject
        The object to serialize. Accepts pipeline input.

        .PARAMETER Depth
        Maximum nesting depth to traverse. Objects deeper than this are rendered via
        their `.ToString()` representation. Default: 1024.

        .PARAMETER EnumsAsStrings
        Renders enum values as their string names instead of their underlying integer values.

        .PARAMETER AsArray
        Forces the top-level output to be a YAML sequence even when a single object is provided.

        .PARAMETER Indent
        Number of spaces to use per nesting level. Default: 2.

        .EXAMPLE
        @{ name = 'Alice'; age = 30 } | ConvertTo-Yaml

        Returns:
        name: Alice
        age: 30

        .EXAMPLE
        Get-Process | Select-Object -First 3 Name, ID | ConvertTo-Yaml -AsArray

        Serializes a list of objects as a YAML sequence.

        .OUTPUTS
        System.String
    #>
    [Alias('ConvertTo-Yml')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [AllowNull()]
        [object] $InputObject,

        [Parameter()]
        [ValidateRange(1, [int]::MaxValue)]
        [int] $Depth = 1024,

        [Parameter()]
        [switch] $EnumsAsStrings,

        [Parameter()]
        [switch] $AsArray,

        [Parameter()]
        [ValidateRange(1, 16)]
        [int] $Indent = 2
    )

    begin {
        $items = [System.Collections.Generic.List[object]]::new()
    }

    process {
        $items.Add($InputObject)
    }

    end {
        $options = [pscustomobject]@{
            Depth          = $Depth
            EnumsAsStrings = [bool] $EnumsAsStrings
            Indent         = $Indent
        }

        $sb = [System.Text.StringBuilder]::new()
        if ($AsArray) {
            ConvertTo-YamlSequence -Value $items.ToArray() -Builder $sb -Level 0 -CurrentDepth 0 -Options $options
        } else {
            $root = if ($items.Count -eq 1) { $items[0] } else { $items.ToArray() }
            ConvertTo-YamlNode -Value $root -Builder $sb -Level 0 -CurrentDepth 0 -Options $options
        }
        return $sb.ToString().TrimEnd("`r", "`n")
    }
}
