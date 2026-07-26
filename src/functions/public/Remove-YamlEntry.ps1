function Remove-YamlEntry {
    <#
        .SYNOPSIS
        Removes entries from a YAML representation graph by JSON Pointer.

        .DESCRIPTION
        Aggregates input strings with a line feed, parses them as one YAML stream,
        deep-clones the representation graph, resolves every RFC 6901 JSON Pointer
        against that unchanged clone, and emits one deterministic YAML string after
        applying the complete removal transaction.

        Mapping tokens address only scalar keys whose effective YAML tag is string
        and whose scalar content is an ordinal match. Complex, non-string, and
        unknown-tagged keys remain intact and are never coerced. Sequence tokens
        must be canonical non-negative decimal indexes. Tilde escapes are strict:
        ~0 decodes to tilde and ~1 decodes to slash.

        Aliases are traversed by node identity. Removing inside a shared collection
        changes every alias to that collection, while targeting an alias edge removes
        only that parent edge. Duplicate logical targets are coalesced, ancestors
        subsume descendants, and sequence entries are removed by descending original
        index.

        Output preserves unaffected tags, anchors, aliases, shared and cyclic graph
        identity, complex keys, mapping order, and document order. It uses LF line
        endings, has no final newline, and explicitly starts every remaining
        document.

        .EXAMPLE
        Get-Content -Path '.\config.yaml' |
            Remove-YamlEntry -Path '/service/obsolete'

        Aggregates file lines and removes one nested mapping entry from document zero.

        .EXAMPLE
        $clean = Remove-YamlEntry -InputObject $yaml -Path @('/metadata/identifier', '/items/2')

        Resolves both paths against the original graph, then applies them atomically.

        .EXAMPLE
        Remove-YamlEntry $stream '/temporary' -AllDocuments -IgnoreMissing -Indent 4

        Removes the key where it exists in every document and emits four-space YAML.

        .EXAMPLE
        Remove-YamlEntry $stream '' -DocumentIndex 1

        Removes the second YAML document from the stream.

        .INPUTS
        System.String[]

        The YAML text to transform. Multiple pipeline records are joined with a line feed.

        .OUTPUTS
        System.String

        The YAML stream emitted after the removal transaction is applied.

        .LINK
        https://psmodule.io/Yaml/Functions/Remove-YamlEntry/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Transforms an isolated in-memory YAML graph and returns text.'
    )]
    [OutputType([string])]
    [CmdletBinding(DefaultParameterSetName = 'Document')]
    param (
        # The YAML text to transform. Multiple array elements or pipeline records
        # are joined with a line feed and parsed as a single stream.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $InputObject,

        # One or more RFC 6901 JSON Pointers to remove. An empty string selects a
        # document root; every non-empty pointer must start with a slash.
        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyString()]
        [string[]] $Path,

        # Zero-based index of the single document to modify.
        [Parameter(ParameterSetName = 'Document')]
        [ValidateRange(0, 2147483647)]
        [int] $DocumentIndex = 0,

        # Apply every path independently to every document in the stream.
        [Parameter(Mandatory, ParameterSetName = 'AllDocuments')]
        [switch] $AllDocuments,

        # Skip unresolved document and path combinations instead of terminating.
        [Parameter()]
        [switch] $IgnoreMissing,

        # Number of spaces per block-indentation level in the emitted YAML.
        [Parameter()]
        [ValidateRange(2, 9)]
        [int] $Indent = 2,

        # Cap YAML node nesting depth so hostile input can't exhaust the stack.
        [Parameter()]
        [ValidateRange(1, 128)]
        [int] $Depth = 100,

        # Cap the total node count across parse, clone, removal, and validation.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes = 100000,

        # Cap alias nodes in the input and result.
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
            $documentBox = Read-YamlStream -Yaml $yamlText -Depth $Depth `
                -MaxNodes $MaxNodes -MaxAliases $MaxAliases `
                -MaxScalarLength $MaxScalarLength -MaxTagLength $MaxTagLength `
                -MaxTotalTagLength $MaxTotalTagLength -MaxNumericLength $MaxNumericLength
            $sourceDocuments = [object[]] $documentBox.Value
            $selectAllDocuments = $AllDocuments.IsPresent
            if (-not $selectAllDocuments -and $DocumentIndex -ge $sourceDocuments.Count) {
                throw (New-YamlRemovalException `
                        -ErrorId 'YamlRemovalDocumentIndexOutOfRange' -Message (
                        "YAML document index $DocumentIndex is unavailable; the stream contains " +
                        "$($sourceDocuments.Count) documents."
                    ))
            }

            $workState = [pscustomobject]@{
                Count    = 0L
                MaxNodes = $MaxNodes
            }
            $parsedPointers = [System.Collections.Generic.List[object]]::new()
            foreach ($pointer in $Path) {
                $tokens = (ConvertFrom-YamlJsonPointer -Pointer $pointer -State $workState).Value
                $parsedPointers.Add([pscustomobject]@{
                        Pointer = $pointer
                        Tokens  = [string[]] $tokens
                    })
            }

            $cloneState = [pscustomobject]@{
                NextId       = 1
                CreatedNodes = 0
                MaxNodes     = $MaxNodes
            }
            $resultDocuments = [System.Collections.Generic.List[object]]::new()
            $cloneCache = [System.Collections.Generic.Dictionary[int, object]]::new()
            try {
                foreach ($sourceDocument in $sourceDocuments) {
                    $resultDocuments.Add((
                            Copy-YamlMergeNode -Node $sourceDocument -Cache $cloneCache `
                                -State $cloneState
                        ))
                }
            } catch {
                if ($_.Exception.Data.Contains('YamlErrorId') -and
                    $_.Exception.Data['YamlErrorId'] -ceq 'YamlMergeNodeLimitExceeded') {
                    throw (New-YamlRemovalException `
                            -ErrorId 'YamlRemovalNodeLimitExceeded' -Message (
                            "Cloning the YAML removal graph exceeded the configured limit of " +
                            "$MaxNodes nodes."
                        ))
                }
                throw
            }
            $resolvedTargets = [System.Collections.Generic.List[object]]::new()
            if ($selectAllDocuments) {
                for ($currentDocumentIndex = 0; $currentDocumentIndex -lt
                    $resultDocuments.Count; $currentDocumentIndex++) {
                    foreach ($parsedPointer in $parsedPointers) {
                        $resolution = Resolve-YamlRemovalTarget `
                            -Document $resultDocuments[$currentDocumentIndex] `
                            -DocumentIndex $currentDocumentIndex `
                            -Pointer $parsedPointer.Pointer -Tokens $parsedPointer.Tokens `
                            -State $workState
                        if ($resolution.Found) {
                            $resolvedTargets.Add($resolution)
                        } elseif (-not $IgnoreMissing) {
                            throw (New-YamlRemovalException -Node $resolution.Node `
                                    -ErrorId $resolution.ErrorId -Message $resolution.Message)
                        }
                    }
                }
            } else {
                foreach ($parsedPointer in $parsedPointers) {
                    $resolution = Resolve-YamlRemovalTarget `
                        -Document $resultDocuments[$DocumentIndex] `
                        -DocumentIndex $DocumentIndex `
                        -Pointer $parsedPointer.Pointer -Tokens $parsedPointer.Tokens `
                        -State $workState
                    if ($resolution.Found) {
                        $resolvedTargets.Add($resolution)
                    } elseif (-not $IgnoreMissing) {
                        throw (New-YamlRemovalException -Node $resolution.Node `
                                -ErrorId $resolution.ErrorId -Message $resolution.Message)
                    }
                }
            }

            $targets = (
                Select-YamlRemovalTarget -Targets ([object[]] $resolvedTargets.ToArray()) `
                    -State $workState
            ).Value
            Remove-YamlRepresentationTarget -Documents $resultDocuments `
                -Targets ([object[]] $targets) -State $workState
            $resultArray = [object[]] $resultDocuments.ToArray()
            $validationState = [pscustomobject]@{
                Count    = 0L
                MaxNodes = $MaxNodes
            }
            Assert-YamlRemovalGraph -Documents $resultArray -Depth $Depth `
                -MaxNodes $MaxNodes -MaxAliases $MaxAliases `
                -MaxScalarLength $MaxScalarLength -MaxTagLength $MaxTagLength `
                -MaxTotalTagLength $MaxTotalTagLength -State $validationState
            $result = ConvertTo-YamlRepresentationText -Documents $resultArray -Indent $Indent
            Write-Debug "Remove-YamlEntry work operations: $($workState.Count)."
            $PSCmdlet.WriteObject($result, $false)
        } catch {
            if (-not $_.Exception.Data.Contains('IsYamlException')) {
                throw
            }
            $record = New-YamlErrorRecord -Exception $_.Exception `
                -DefaultErrorId 'YamlRemovalFailed' -Category InvalidData `
                -TargetObject $yamlText
            $PSCmdlet.ThrowTerminatingError($record)
        }
    }
}
