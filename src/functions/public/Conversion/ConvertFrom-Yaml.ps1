function ConvertFrom-Yaml {
    <#
        .SYNOPSIS
        Converts a YAML stream into PowerShell values.

        .DESCRIPTION
        Parses YAML with the module's repository-owned YAML 1.2 parser and
        constructs values with the core schema. Mapping keys must be unique.
        Unknown application tags never activate .NET types and are treated as
        neutral metadata.

        Pipeline strings are joined with a line feed and parsed as one stream,
        which supports Get-Content. Each YAML document is written separately.

        Mapping and sequence documents carry the PSModule.Yaml.Document type name and
        a ToString that renders the value as YAML text, so a parsed value can be shown
        in its source notation. Scalar documents keep their own ToString.

        .EXAMPLE
        'name: Ada' | ConvertFrom-Yaml

        Converts one mapping to a PSCustomObject.

        .EXAMPLE
        ('name: Ada' | ConvertFrom-Yaml).ToString()

        Renders the parsed mapping back to YAML text.

        .EXAMPLE
        Get-Content -Path '.\config.yaml' | ConvertFrom-Yaml -AsHashtable

        Joins the input lines and returns ordered dictionaries.

        .INPUTS
        System.String[]

        The YAML text to parse. Multiple pipeline records are joined with a line feed.

        .OUTPUTS
        System.Object

        The PowerShell value constructed from each YAML document in the stream.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        # The YAML text to parse. Multiple pipeline records are joined with a
        # line feed and parsed as a single stream, which supports Get-Content.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $Yaml,

        # Return mappings as insertion-ordered dictionaries so complex, non-string,
        # empty, or case-colliding keys survive intact.
        [Parameter()]
        [switch] $AsHashtable,

        # Write each top-level sequence as a single array record instead of
        # enumerating its items onto the pipeline.
        [Parameter()]
        [switch] $NoEnumerate,

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
        foreach ($line in $Yaml) {
            $lines.Add($line)
        }
    }
    end {
        $yamlText = $lines -join "`n"
        try {
            $documentBox = Read-YamlStream -Yaml $yamlText -Depth $Depth -MaxNodes $MaxNodes `
                -MaxAliases $MaxAliases -MaxScalarLength $MaxScalarLength -MaxTagLength $MaxTagLength `
                -MaxTotalTagLength $MaxTotalTagLength -MaxNumericLength $MaxNumericLength
            foreach ($document in $documentBox.Value) {
                $cache = [System.Collections.Generic.Dictionary[int, object]]::new()
                $valueBox = ConvertFrom-YamlNode -Node $document -AsHashtable:$AsHashtable -Cache $cache
                $value = $valueBox.Value

                $effectiveNode = $document
                while ($effectiveNode.Kind -eq 'Alias') {
                    $effectiveNode = $effectiveNode.Target
                }
                $isTopLevelSequence = $effectiveNode.Kind -eq 'Sequence' -and $effectiveNode.Tag -ne 'tag:yaml.org,2002:omap'

                if ($isTopLevelSequence -and -not $NoEnumerate) {
                    foreach ($item in $value) {
                        Add-YamlToStringMember -Value $item
                        $PSCmdlet.WriteObject($item, $false)
                    }
                } else {
                    Add-YamlToStringMember -Value $value
                    $PSCmdlet.WriteObject($value, $false)
                }
            }
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
