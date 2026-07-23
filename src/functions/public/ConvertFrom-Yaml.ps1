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

        .PARAMETER Yaml
        YAML text. Multiple pipeline records are joined with a line feed and
        parsed as one YAML stream.

        .PARAMETER AsHashtable
        Returns mappings as insertion-ordered dictionaries. Use this for
        complex, non-string, empty, or case-colliding mapping keys.

        .PARAMETER NoEnumerate
        Writes each top-level YAML sequence as one array pipeline record.

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
        'name: Ada' | ConvertFrom-Yaml

        Converts one mapping to a PSCustomObject.

        .EXAMPLE
        Get-Content -Path '.\config.yaml' | ConvertFrom-Yaml -AsHashtable

        Joins the input lines and returns ordered dictionaries.

        .INPUTS
        System.String[]

        .OUTPUTS
        System.Object
    #>
    [CmdletBinding()]
    [OutputType([object])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $Yaml,

        [switch] $AsHashtable,

        [switch] $NoEnumerate,

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
                        $PSCmdlet.WriteObject($item, $false)
                    }
                } else {
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
