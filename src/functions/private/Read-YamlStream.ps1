function Read-YamlStream {
    <#
        .SYNOPSIS
        Parses YAML text without text repair or external parser dependencies.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Yaml,

        [Parameter(Mandatory)]
        [ValidateRange(1, 128)]
        [int] $Depth,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes,

        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [int] $MaxAliases,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1048576)]
        [int] $MaxTagLength,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxTotalTagLength,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1048576)]
        [int] $MaxNumericLength
    )

    Read-YamlStreamCore -Yaml $Yaml -Depth $Depth -MaxNodes $MaxNodes -MaxAliases $MaxAliases `
        -MaxScalarLength $MaxScalarLength -MaxTagLength $MaxTagLength `
        -MaxTotalTagLength $MaxTotalTagLength -MaxNumericLength $MaxNumericLength
}
