function Format-Yaml {
    <#
        .SYNOPSIS
        Normalizes a YAML stream without projecting it to PowerShell values.

        .DESCRIPTION
        Parses YAML into the module's representation graph and emits one
        deterministic YAML string directly from those nodes. Document order,
        empty documents, effective tags, anchors, aliases, complex keys, node
        kinds, scalar content, and mapping order are preserved.

        Comments, directives, flow styles, scalar presentation styles, document
        end markers, and source anchor names are normalized. Every document has
        an explicit start marker. Output uses LF and has no final newline.

        Pipeline strings are joined with a line feed and parsed as one stream,
        matching ConvertFrom-Yaml.

        .PARAMETER InputObject
        YAML text. Multiple pipeline records are joined with a line feed and
        parsed as one YAML stream.

        .PARAMETER Indent
        Block indentation from 2 through 9 spaces. The default is 2.

        .PARAMETER Depth
        Maximum YAML node nesting depth. The default is 100.

        .PARAMETER MaxNodes
        Maximum number of YAML nodes in the stream. The default is 100000.

        .PARAMETER MaxAliases
        Maximum number of alias nodes in the stream. The default is 1000.

        .PARAMETER MaxScalarLength
        Maximum decoded character count for one scalar. The default is
        1048576.

        .PARAMETER MaxTagLength
        Maximum expanded character count for one tag. The default is 1024.

        .PARAMETER MaxTotalTagLength
        Maximum cumulative expanded tag characters. The default is 65536.

        .PARAMETER MaxNumericLength
        Maximum digits in an implicitly or explicitly typed number. The
        default is 4096.

        .EXAMPLE
        Get-Content -Path '.\config.yaml' | Format-Yaml

        Joins the input lines and emits one normalized YAML stream.

        .EXAMPLE
        $normalized = Format-Yaml -InputObject '{name: Ada, active: true}' -Indent 4

        Converts flow presentation to deterministic block presentation with
        four-space indentation.

        .INPUTS
        System.String[]

        .OUTPUTS
        System.String

        .LINK
        https://github.com/PSModule/Yaml#format-yaml-streams
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $InputObject,

        [ValidateRange(2, 9)]
        [int] $Indent = 2,

        [ValidateRange(1, 128)]
        [int] $Depth = 100,

        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes = 100000,

        [ValidateRange(0, 2147483647)]
        [int] $MaxAliases = 1000,

        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength = 1048576,

        [ValidateRange(1, 1048576)]
        [int] $MaxTagLength = 1024,

        [ValidateRange(1, 2147483647)]
        [int] $MaxTotalTagLength = 65536,

        [ValidateRange(1, 1048576)]
        [int] $MaxNumericLength = 4096
    )

    begin {
        $lines = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach ($line in $InputObject) {
            $lines.Add($line)
        }
    }
    end {
        $yamlText = $lines -join "`n"
        try {
            $documentBox = Read-YamlStream -Yaml $yamlText -Depth $Depth -MaxNodes $MaxNodes `
                -MaxAliases $MaxAliases -MaxScalarLength $MaxScalarLength -MaxTagLength $MaxTagLength `
                -MaxTotalTagLength $MaxTotalTagLength -MaxNumericLength $MaxNumericLength
            $formatted = ConvertTo-YamlRepresentationText -Documents $documentBox.Value -Indent $Indent
            $PSCmdlet.WriteObject($formatted, $false)
        } catch {
            if (-not $_.Exception.Data.Contains('IsYamlException')) {
                throw
            }
            $record = New-YamlErrorRecord -Exception $_.Exception -DefaultErrorId 'YamlInvalidInput' `
                -Category InvalidData -TargetObject $yamlText
            $PSCmdlet.ThrowTerminatingError($record)
        }
    }
}
