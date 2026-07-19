function Test-Yaml {
    <#
        .SYNOPSIS
        Tests whether text is a valid, safely processable YAML stream.

        .DESCRIPTION
        Parses a YAML stream, checks unique mapping keys, validates standard
        tags, and applies the same resource limits as ConvertFrom-Yaml. It
        returns false only for YamlDotNet YAML exceptions. Unexpected runtime
        failures are not swallowed.

        Pipeline strings are joined with a line feed and tested as one stream.

        .PARAMETER Yaml
        YAML text. Multiple pipeline records are joined with a line feed.

        .PARAMETER Depth
        Maximum YAML node nesting depth. The default is 100.

        .PARAMETER MaxNodes
        Maximum number of YAML nodes in the stream. The default is 100000.

        .PARAMETER MaxAliases
        Maximum number of alias nodes in the stream. The default is 1000.

        .PARAMETER MaxScalarLength
        Maximum decoded character count for one scalar. The default is
        1048576.

        .EXAMPLE
        'name: Ada' | Test-Yaml

        Returns true.

        .INPUTS
        System.String[]

        .OUTPUTS
        System.Boolean
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $Yaml,

        [ValidateRange(1, 1024)]
        [int] $Depth = 100,

        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes = 100000,

        [ValidateRange(0, 2147483647)]
        [int] $MaxAliases = 1000,

        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength = 1048576
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
                -MaxAliases $MaxAliases -MaxScalarLength $MaxScalarLength
            $PSCmdlet.WriteObject($true)
        } catch [YamlDotNet.Core.YamlException] {
            $PSCmdlet.WriteObject($false)
        }
    }
}
