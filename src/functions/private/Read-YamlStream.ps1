function Read-YamlStream {
    <#
        .SYNOPSIS
        Parses YAML text without text repair or external parser dependencies.

        .DESCRIPTION
        Passes a complete YAML stream to the module-owned reader core with the
        resource limits configured by ConvertFrom-Yaml. This keeps stream parsing
        strict while preserving the public command's safety budgets.

        .EXAMPLE
        Read-YamlStream -Yaml $yaml -Depth 100 -MaxNodes 100000 -MaxAliases 1000 -MaxScalarLength 1048576 -MaxTagLength 1024 -MaxTotalTagLength 65536 -MaxNumericLength 4096

        Parses the supplied YAML stream and returns the boxed document collection.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # Complete YAML source text collected from the public command input.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Yaml,

        # Maximum representation depth allowed while building the node graph.
        [Parameter(Mandatory)]
        [ValidateRange(1, 128)]
        [int] $Depth,

        # Total node budget used to reject oversized YAML documents.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes,

        # Alias reference budget that prevents excessive anchor expansion work.
        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [int] $MaxAliases,

        # Maximum decoded scalar length accepted before constructing values.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength,

        # Per-token expanded tag length budget for directives and node tags.
        [Parameter(Mandatory)]
        [ValidateRange(1, 1048576)]
        [int] $MaxTagLength,

        # Cumulative expanded tag length budget for the complete YAML stream.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxTotalTagLength,

        # Maximum numeric scalar length accepted by schema construction.
        [Parameter(Mandatory)]
        [ValidateRange(1, 1048576)]
        [int] $MaxNumericLength
    )

    Read-YamlStreamCore -Yaml $Yaml -Depth $Depth -MaxNodes $MaxNodes -MaxAliases $MaxAliases `
        -MaxScalarLength $MaxScalarLength -MaxTagLength $MaxTagLength `
        -MaxTotalTagLength $MaxTotalTagLength -MaxNumericLength $MaxNumericLength
}
