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

        .EXAMPLE
        Get-Content -Path '.\config.yaml' | Format-Yaml

        Joins the input lines and emits one normalized YAML stream.

        .EXAMPLE
        $normalized = Format-Yaml -InputObject '{name: Ada, active: true}' -Indent 4

        Converts flow presentation to deterministic block presentation with
        four-space indentation.

        .INPUTS
        System.String[]

        The YAML text to normalize. Multiple pipeline records are joined with a line feed.

        .OUTPUTS
        System.String

        The normalized YAML stream emitted from the representation graph.

        .LINK
        https://psmodule.io/Yaml/Functions/Streams/Format-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The YAML text to normalize. Multiple pipeline records are joined with
        # a line feed and parsed as a single stream, matching ConvertFrom-Yaml.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $InputObject,

        # Number of spaces per block-indentation level in the emitted YAML.
        [Parameter()]
        [ValidateRange(2, 9)]
        [int] $Indent = 2,

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

        # Cap the digit count of an implicitly or explicitly typed number.
        [Parameter()]
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
