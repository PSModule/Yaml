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

        .PARAMETER InputObject
        YAML text. Multiple array elements or pipeline records are joined with a
        line feed and parsed as one YAML stream.

        .PARAMETER Path
        One or more RFC 6901 JSON Pointers. An empty string selects a document root.
        Every non-empty pointer must start with slash.

        .PARAMETER DocumentIndex
        Zero-based document index to modify. The default is 0.

        .PARAMETER AllDocuments
        Applies every path independently to every document in the original stream.

        .PARAMETER IgnoreMissing
        Skips unresolved document and path combinations. Invalid pointer syntax,
        invalid sequence index tokens, ambiguous matches, and an unavailable
        DocumentIndex still terminate.

        .PARAMETER Indent
        Block indentation from 2 through 9 spaces. The default is 2.

        .PARAMETER Depth
        Maximum YAML node nesting depth. The default is 100.

        .PARAMETER MaxNodes
        Maximum YAML nodes in the input and result, and the invocation-wide ceiling
        applied independently to clone creation, removal work, and output validation.
        The default is 100000.

        .PARAMETER MaxAliases
        Maximum aliases in the input and result. The default is 1000.

        .PARAMETER MaxScalarLength
        Maximum decoded character count for one scalar. The default is 1048576.

        .PARAMETER MaxTagLength
        Maximum expanded character count for one tag. The default is 1024.

        .PARAMETER MaxTotalTagLength
        Maximum cumulative expanded tag characters. The default is 65536.

        .PARAMETER MaxNumericLength
        Maximum digits in an implicitly or explicitly typed number. The default is
        4096.

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

        .OUTPUTS
        System.String

        .LINK
        https://github.com/PSModule/Yaml#remove-yaml-entries
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Transforms an isolated in-memory YAML graph and returns text.'
    )]
    [OutputType([string])]
    [CmdletBinding(DefaultParameterSetName = 'Document')]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $InputObject,

        [Parameter(Mandatory, Position = 1)]
        [AllowEmptyString()]
        [string[]] $Path,

        [Parameter(ParameterSetName = 'Document')]
        [ValidateRange(0, 2147483647)]
        [int] $DocumentIndex = 0,

        [Parameter(Mandatory, ParameterSetName = 'AllDocuments')]
        [switch] $AllDocuments,

        [Parameter()]
        [switch] $IgnoreMissing,

        [Parameter()]
        [ValidateRange(2, 9)]
        [int] $Indent = 2,

        [Parameter()]
        [ValidateRange(1, 128)]
        [int] $Depth = 100,

        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes = 100000,

        [Parameter()]
        [ValidateRange(0, 2147483647)]
        [int] $MaxAliases = 1000,

        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength = 1048576,

        [Parameter()]
        [ValidateRange(1, 1048576)]
        [int] $MaxTagLength = 1024,

        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxTotalTagLength = 65536,

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
