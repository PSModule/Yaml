function Read-YamlStream {
    <#
        .SYNOPSIS
        Parses YAML text with a narrow parser-compatibility retry.
    #>
    [CmdletBinding()]
    [OutputType([object[]])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Yaml,

        [Parameter(Mandatory)]
        [ValidateRange(1, 1024)]
        [int] $Depth,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes,

        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [int] $MaxAliases,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength
    )

    try {
        Write-Output -InputObject (
            Read-YamlStreamCore -Yaml $Yaml -Depth $Depth -MaxNodes $MaxNodes `
                -MaxAliases $MaxAliases -MaxScalarLength $MaxScalarLength
        ) -NoEnumerate
    } catch [YamlDotNet.Core.SemanticErrorException] {
        $compatibleYaml = ConvertTo-YamlParserCompatibleText -Yaml $Yaml
        if ($compatibleYaml -ceq $Yaml) {
            throw
        }
        Write-Output -InputObject (
            Read-YamlStreamCore -Yaml $compatibleYaml -Depth $Depth -MaxNodes $MaxNodes `
                -MaxAliases $MaxAliases -MaxScalarLength $MaxScalarLength
        ) -NoEnumerate
    } catch [System.Management.Automation.MethodInvocationException] {
        if ($_.Exception.InnerException -is [YamlDotNet.Core.SemanticErrorException]) {
            $compatibleYaml = ConvertTo-YamlParserCompatibleText -Yaml $Yaml
            if ($compatibleYaml -ceq $Yaml) {
                throw $_.Exception.InnerException
            }
            Write-Output -InputObject (
                Read-YamlStreamCore -Yaml $compatibleYaml -Depth $Depth -MaxNodes $MaxNodes `
                    -MaxAliases $MaxAliases -MaxScalarLength $MaxScalarLength
            ) -NoEnumerate
            return
        }
        if ($_.Exception.InnerException -isnot [System.InvalidOperationException]) {
            throw
        }
        throw (New-YamlException -Start ([YamlDotNet.Core.Mark]::Empty) `
                -End ([YamlDotNet.Core.Mark]::Empty) -ErrorId 'YamlInvalidSyntax' -Message (
                'YamlDotNet entered an invalid parser state while reading malformed YAML.'
            ))
    }
}
