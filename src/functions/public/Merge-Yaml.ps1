function Merge-Yaml {
    <#
        .SYNOPSIS
        Merges two or more complete YAML streams.

        .DESCRIPTION
        Parses every input string as one complete YAML stream, merges documents
        pairwise by zero-based document index, and emits one deterministic YAML
        string directly from the resulting representation graphs. Every stream
        must contain the same positive number of documents. Later streams have
        higher precedence.

        Compatible mappings merge recursively by YAML structural key equality.
        Base key order is retained, replaced values keep their position, and new
        overlay keys append in overlay order. Tags, complex keys, anchors,
        aliases, shared nodes, and recursive graphs remain representation data;
        values are never projected through PowerShell objects or dictionaries.

        Output uses LF line endings, has no final newline, and explicitly starts
        every document. Input array elements and pipeline records are complete
        streams, not individual lines. Use Get-Content -Raw or Import-Yaml file
        handling as appropriate.

        .PARAMETER InputObject
        Two or more complete YAML stream strings. Each array element or pipeline
        record is parsed independently as one stream.

        .PARAMETER SequenceAction
        Action for unequal sequences with compatible effective tags. Replace uses
        the later sequence, Append concatenates entries, and Unique appends only
        structurally new entries. The default is Replace.

        .PARAMETER ConflictAction
        Action for unequal scalars, collection-kind differences, or incompatible
        effective tags. Replace uses the later node and Error terminates with
        document, path, and input context. The default is Replace.

        .PARAMETER NullAction
        Action when a later existing node has the YAML null effective tag.
        Replace applies normal merge and conflict behavior; Ignore retains the
        prior node. The default is Replace.

        .PARAMETER Indent
        Block indentation from 2 through 9 spaces. The default is 2.

        .PARAMETER Depth
        Maximum YAML node nesting depth. The default is 100.

        .PARAMETER MaxNodes
        Maximum nodes per parsed stream and the invocation-wide ceiling applied
        independently to clone creation, merge operations, and the result graph.
        The default is 100000.

        .PARAMETER MaxAliases
        Maximum aliases per parsed stream and in the result. The default is 1000.

        .PARAMETER MaxScalarLength
        Maximum decoded character count for one scalar. The default is 1048576.

        .PARAMETER MaxTagLength
        Maximum expanded character count for one tag. The default is 1024.

        .PARAMETER MaxTotalTagLength
        Maximum cumulative expanded tag characters per input and in the result.
        The default is 65536.

        .PARAMETER MaxNumericLength
        Maximum digits in an implicitly or explicitly typed number. The default
        is 4096.

        .EXAMPLE
        $merged = Merge-Yaml -InputObject @($baseYaml, $overlayYaml)

        Merges two complete stream strings with the overlay taking precedence.

        .EXAMPLE
        $baseYaml, $environmentYaml, $secretYaml | Merge-Yaml -SequenceAction Unique

        Merges three complete pipeline stream records and deduplicates compatible
        sequence entries structurally.

        .EXAMPLE
        $base = Get-Content -LiteralPath '.\base.yaml' -Raw
        $overlay = Get-Content -LiteralPath '.\overlay.yaml' -Raw
        Merge-Yaml -InputObject @($base, $overlay) -ConflictAction Error -Indent 4

        Reads complete files and rejects incompatible merge conflicts.

        .INPUTS
        System.String[]

        .OUTPUTS
        System.String

        .NOTES
        YAML 1.1 merge keys are ordinary mapping data and are never expanded.

        .LINK
        https://github.com/PSModule/Yaml#format-yaml-streams
    #>
    [OutputType([string])]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowEmptyString()]
        [string[]] $InputObject,

        [Parameter()]
        [ValidateSet('Replace', 'Append', 'Unique')]
        [string] $SequenceAction = 'Replace',

        [Parameter()]
        [ValidateSet('Replace', 'Error')]
        [string] $ConflictAction = 'Replace',

        [Parameter()]
        [ValidateSet('Replace', 'Ignore')]
        [string] $NullAction = 'Replace',

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
        $streams = [System.Collections.Generic.List[string]]::new()
    }
    process {
        foreach ($stream in $InputObject) {
            $streams.Add($stream)
        }
    }
    end {
        $fingerprintHasher = $null
        try {
            if ($streams.Count -lt 2) {
                throw (New-YamlMergeException -ErrorId 'YamlMergeInputCount' -Message (
                        "Merge-Yaml requires at least two complete YAML streams; received $($streams.Count)."
                    ))
            }

            $parsedStreams = [System.Collections.Generic.List[object]]::new()
            $expectedDocumentCount = -1
            for ($inputIndex = 0; $inputIndex -lt $streams.Count; $inputIndex++) {
                $documentBox = Read-YamlStream -Yaml $streams[$inputIndex] -Depth $Depth `
                    -MaxNodes $MaxNodes -MaxAliases $MaxAliases `
                    -MaxScalarLength $MaxScalarLength -MaxTagLength $MaxTagLength `
                    -MaxTotalTagLength $MaxTotalTagLength -MaxNumericLength $MaxNumericLength
                $documents = [object[]] $documentBox.Value
                if ($documents.Count -eq 0) {
                    throw (New-YamlMergeException -ErrorId 'YamlMergeEmptyStream' -Message (
                            "YAML input index $inputIndex contains 0 documents; every stream must contain " +
                            'the same positive document count.'
                        ))
                }
                if ($inputIndex -eq 0) {
                    $expectedDocumentCount = $documents.Count
                } elseif ($documents.Count -ne $expectedDocumentCount) {
                    throw (New-YamlMergeException `
                            -ErrorId 'YamlMergeDocumentCountMismatch' -Message (
                            "YAML input index $inputIndex contains $($documents.Count) documents; " +
                            "expected $expectedDocumentCount."
                        ))
                }
                $parsedStreams.Add($documents)
            }

            $cloneState = [pscustomobject]@{
                NextId       = 1
                CreatedNodes = 0
                MaxNodes     = $MaxNodes
            }
            $resultDocuments = [System.Collections.Generic.List[object]]::new()
            $baseCache = [System.Collections.Generic.Dictionary[int, object]]::new()
            foreach ($document in $parsedStreams[0]) {
                $resultDocuments.Add((
                        Copy-YamlMergeNode -Node $document -Cache $baseCache -State $cloneState
                    ))
            }

            $fingerprintHasher = [System.Security.Cryptography.SHA256]::Create()
            $workState = [pscustomobject]@{
                Count    = 0L
                MaxNodes = $MaxNodes
            }
            $mutationState = [pscustomobject]@{ Version = 0L }
            $indexDependents = [System.Collections.Generic.Dictionary[int, object]]::new()
            $equalityState = [pscustomobject]@{
                MaxNodes          = $MaxNodes
                FingerprintHasher = $fingerprintHasher
                WorkState         = $workState
                MutationState     = $mutationState
                IndexDependents   = $indexDependents
                Cache             = [System.Collections.Generic.Dictionary[string, bool]]::new(
                    [System.StringComparer]::Ordinal
                )
                InputIndex        = 0
            }
            $mappingIndexes = [System.Collections.Generic.Dictionary[int, object]]::new()
            $sequenceIndexes = [System.Collections.Generic.Dictionary[int, object]]::new()
            for ($inputIndex = 1; $inputIndex -lt $parsedStreams.Count; $inputIndex++) {
                $cloneCache = [System.Collections.Generic.Dictionary[int, object]]::new()
                $overlayFingerprintCache = (
                    [System.Collections.Generic.Dictionary[int, string]]::new()
                )
                $equalityState.InputIndex = $inputIndex
                foreach ($documentIndex in 0..($expectedDocumentCount - 1)) {
                    $context = [pscustomobject]@{
                        InputIndex              = $inputIndex
                        DocumentIndex           = $documentIndex
                        CloneCache              = $cloneCache
                        CloneState              = $cloneState
                        EqualityState           = $equalityState
                        WorkState               = $workState
                        MutationState           = $mutationState
                        MappingIndexes          = $mappingIndexes
                        SequenceIndexes         = $sequenceIndexes
                        IndexDependents         = $indexDependents
                        OverlayFingerprintCache = $overlayFingerprintCache
                    }
                    $resultDocuments[$documentIndex] = Merge-YamlRepresentationNode `
                        -BaseNode $resultDocuments[$documentIndex] `
                        -OverlayNode $parsedStreams[$inputIndex][$documentIndex] `
                        -SequenceAction $SequenceAction -ConflictAction $ConflictAction `
                        -NullAction $NullAction -Path '$' -Context $context
                }
            }

            $resultArray = [object[]] $resultDocuments.ToArray()
            Assert-YamlMergeGraph -Documents $resultArray -Depth $Depth -MaxNodes $MaxNodes `
                -MaxAliases $MaxAliases -MaxScalarLength $MaxScalarLength `
                -MaxTagLength $MaxTagLength -MaxTotalTagLength $MaxTotalTagLength
            $merged = ConvertTo-YamlRepresentationText -Documents $resultArray -Indent $Indent
            Write-Debug "Merge-Yaml work operations: $($workState.Count)."
            $PSCmdlet.WriteObject($merged, $false)
        } catch {
            $failure = $_
            if (-not $failure.Exception.Data.Contains('IsYamlException')) {
                throw
            }
            $record = New-YamlErrorRecord -Exception $failure.Exception `
                -DefaultErrorId 'YamlMergeFailed' -Category InvalidData `
                -TargetObject $streams.ToArray()
            $PSCmdlet.ThrowTerminatingError($record)
        } finally {
            if ($null -ne $fingerprintHasher) {
                $fingerprintHasher.Dispose()
            }
        }
    }
}
