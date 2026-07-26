function Test-Yaml {
    <#
        .SYNOPSIS
        Tests whether text is a valid, safely processable YAML stream.

        .DESCRIPTION
        Parses a YAML stream, checks unique mapping keys, validates standard
        tags, and applies the same resource limits as ConvertFrom-Yaml. It
        returns false only for module-classified YAML failures. Unexpected
        runtime failures are not swallowed.

        Pipeline strings are joined with a line feed and tested as one stream.

        .EXAMPLE
        'name: Ada' | Test-Yaml

        Returns true.

        .INPUTS
        System.String[]

        The YAML text to test. Multiple pipeline records are joined with a line feed.

        .OUTPUTS
        System.Boolean

        True when the stream parses within limits; false for a classified YAML failure.

        .LINK
        https://psmodule.io/Yaml/Functions/Test-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        # The YAML text to test. Multiple pipeline records are joined with a
        # line feed and tested as a single stream.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $Yaml,

        # Cap YAML node nesting depth so hostile input can't exhaust the stack.
        [Parameter()]
        [ValidateRange(1, 128)]
        [int] $Depth = 100,

        # Cap the total node count to bound memory for a single stream.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes = 100000,

        # Cap alias nodes to prevent alias-expansion amplification.
        [Parameter()]
        [ValidateRange(0, 2147483647)]
        [int] $MaxAliases = 1000,

        # Cap decoded characters per scalar to bound per-node memory.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength = 1048576,

        # Cap expanded characters for a single tag.
        [Parameter()]
        [ValidateRange(1, 1048576)]
        [int] $MaxTagLength = 1024,

        # Cap cumulative expanded tag characters across the stream.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxTotalTagLength = 65536,

        # Cap the digit count of a constructed number.
        [Parameter()]
        [ValidateRange(1, 1048576)]
        [int] $MaxNumericLength = 4096
    )

    begin {
        $lines = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach ($line in $Yaml) {
            $lines.Add($line)
        }
    }
    end {
        try {
            $null = Read-YamlStream -Yaml ($lines -join "`n") -Depth $Depth -MaxNodes $MaxNodes `
                -MaxAliases $MaxAliases -MaxScalarLength $MaxScalarLength -MaxTagLength $MaxTagLength `
                -MaxTotalTagLength $MaxTotalTagLength -MaxNumericLength $MaxNumericLength
            $PSCmdlet.WriteObject($true)
        } catch {
            if (-not $_.Exception.Data.Contains('IsYamlException')) {
                throw
            }
            $PSCmdlet.WriteObject($false)
        }
    }
}
