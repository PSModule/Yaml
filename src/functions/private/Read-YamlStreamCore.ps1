function Read-YamlStreamCore {
    <#
        .SYNOPSIS
        Reads and validates all documents with the repository-owned YAML parser.

        .DESCRIPTION
        Creates the reader context, scans directives and document boundaries,
        reads each document node, and converts syntax trees into representation
        graph values. It is the core parser path behind ConvertFrom-Yaml.

        .EXAMPLE
        Read-YamlStreamCore -Yaml $yaml -Depth 100 -MaxNodes 100000 -MaxAliases 1000 -MaxScalarLength 1048576 -MaxTagLength 1024 -MaxTotalTagLength 65536 -MaxNumericLength 4096

        Reads all documents in the stream and returns them as a boxed array.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # Complete YAML source text to split into documents and parse.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Yaml,

        # Maximum representation depth permitted while reading nested nodes.
        [Parameter(Mandatory)]
        [ValidateRange(1, 128)]
        [int] $Depth,

        # Node budget used by syntax-node creation and graph validation.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes,

        # Alias reference budget enforced while composing anchored nodes.
        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [int] $MaxAliases,

        # Maximum decoded scalar length allowed across scalar readers.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength,

        # Per-token tag limit used when parsing directives and node properties.
        [Parameter(Mandatory)]
        [ValidateRange(1, 1048576)]
        [int] $MaxTagLength,

        # Stream-wide expanded tag budget shared by tag resolution.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $MaxTotalTagLength,

        # Maximum numeric scalar length passed to core schema construction.
        [Parameter(Mandatory)]
        [ValidateRange(1, 1048576)]
        [int] $MaxNumericLength,

        # Allows callers that validate later to skip immediate graph validation.
        [Parameter()]
        [switch] $SkipGraphValidation
    )

    $context = New-YamlReaderContext -Yaml $Yaml -Depth $Depth -MaxNodes $MaxNodes `
        -MaxAliases $MaxAliases -MaxScalarLength $MaxScalarLength `
        -MaxTagLength $MaxTagLength -MaxTotalTagLength $MaxTotalTagLength `
        -MaxNumericLength $MaxNumericLength
    $lines = $context.Lines
    $lineStarts = $context.LineStarts
    $documents = [System.Collections.Generic.List[object]]::new()
    $implicitDocumentSeen = $false

    while ($context.LineIndex -lt $lines.Count) {
        Skip-YamlDocumentPrefix -Context $context
        if ($context.LineIndex -ge $lines.Count) {
            break
        }
        if ($lines[$context.LineIndex] -match '^\.\.\.(?:[ \t]|$)') {
            $mark = New-YamlMark -Index ($lineStarts[$context.LineIndex] + 3) `
                -Line $context.LineIndex -Column 3
            $suffix = Get-YamlContentWithoutComment `
                -Text $lines[$context.LineIndex].Substring(3) -Mark $mark
            if ($suffix.Trim(' ', "`t").Length -gt 0) {
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidDocumentEnd' -Message (
                        'Unexpected content follows the document end marker.'
                    ))
            }
            $context.LineIndex++
            $implicitDocumentSeen = $false
            continue
        }

        $directives = Read-YamlDirectiveBlock -Context $context
        $tagHandles = $directives.TagHandles
        $directiveSeen = $directives.DirectiveSeen

        if ($context.LineIndex -ge $lines.Count) {
            if ($directiveSeen) {
                $mark = New-YamlMark -Index $context.Text.Length `
                    -Line ([Math]::Max(0, $lines.Count - 1)) -Column 0
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlDirectiveWithoutDocument' -Message (
                        'YAML directives must be followed by an explicit document start marker.'
                    ))
            }
            break
        }

        $lineText = $lines[$context.LineIndex]
        $explicitStart = $lineText -match '^---(?:[ \t]|$)'
        if ($directiveSeen -and -not $explicitStart) {
            $mark = New-YamlMark -Index $lineStarts[$context.LineIndex] -Line $context.LineIndex -Column 0
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlDirectiveWithoutDocument' -Message (
                    'YAML directives must be followed by an explicit document start marker.'
                ))
        }
        if (-not $explicitStart -and $implicitDocumentSeen) {
            $mark = New-YamlMark -Index $lineStarts[$context.LineIndex] -Line $context.LineIndex -Column 0
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidStream' -Message (
                    'A second document requires an explicit document start marker.'
                ))
        }

        $context.TagHandles = $tagHandles
        $context.Anchors = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        if ($explicitStart) {
            $afterMarker = $lineText.Substring(3)
            $leading = $afterMarker.Length - $afterMarker.TrimStart(' ', "`t").Length
            $segment = $afterMarker.TrimStart(' ', "`t")
            $segmentColumn = 3 + $leading
            $segmentMark = New-YamlMark -Index (
                $lineStarts[$context.LineIndex] + $segmentColumn
            ) -Line $context.LineIndex -Column $segmentColumn
            if ([string]::IsNullOrEmpty((
                        Get-YamlContentWithoutComment -Text $segment -Mark $segmentMark
                    ))) {
                $markerLine = $context.LineIndex
                $context.LineIndex++
                Skip-YamlBlockTrivia -Context $context
                if ($context.LineIndex -ge $lines.Count -or
                    $lines[$context.LineIndex] -match '^(?:---|\.\.\.)(?:[ \t]|$)' -or
                    (Test-YamlDocumentByteOrderMark -Context $context -RequireDocumentStart)) {
                    $mark = New-YamlMark -Index ($lineStarts[$markerLine] + 3) -Line $markerLine -Column 3
                    $document = New-YamlEmptyScalar -Context $context -Depth 1 -Mark $mark
                } else {
                    $document = Read-YamlBlockNode -Context $context -ParentIndent -1 -Depth 1
                }
            } else {
                if ($segment[0] -in @('!', '&') -and
                    (Find-YamlMappingColon -Text $segment -AllowAnchorFallback) -ge 0) {
                    $mark = New-YamlMark -Index ($lineStarts[$context.LineIndex] + $segmentColumn) `
                        -Line $context.LineIndex -Column $segmentColumn
                    throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidDocumentStart' -Message (
                            'Node properties cannot precede a compact block mapping on a document-start line.'
                        ))
                }
                if (-not (Test-YamlIndicator -Text $segment -Indicator '-') -and
                    ((Find-YamlMappingColon -Text $segment -AllowAnchorFallback) -ge 0 -or
                    (Test-YamlIndicator -Text $segment -Indicator '?'))) {
                    $document = Read-YamlBlockMapping -Context $context -Indent 0 -Depth 1 `
                        -FirstText $segment -FirstColumn $segmentColumn
                } elseif (Test-YamlIndicator -Text $segment -Indicator '-') {
                    $firstItem = $segment.Substring(1)
                    $leading = $firstItem.Length - $firstItem.TrimStart(' ', "`t").Length
                    $document = Read-YamlBlockSequence -Context $context -Indent 0 -Depth 1 `
                        -FirstItemText $firstItem.TrimStart(' ', "`t") `
                        -FirstItemColumn ($segmentColumn + 1 + $leading)
                } else {
                    $document = Read-YamlBlockNode -Context $context -ParentIndent -1 -Depth 1 `
                        -Segment $segment -SegmentColumn $segmentColumn
                }
            }
        } else {
            $implicitDocumentSeen = $true
            $document = Read-YamlBlockNode -Context $context -ParentIndent -1 -Depth 1
        }

        $document = ConvertFrom-YamlSyntaxTree -Root $document
        if (-not $SkipGraphValidation) {
            $fingerprintHasher = [System.Security.Cryptography.SHA256]::Create()
            try {
                Test-YamlNodeGraph -Node $document -Visited ([System.Collections.Generic.HashSet[int]]::new()) `
                    -FingerprintCache ([System.Collections.Generic.Dictionary[int, string]]::new()) `
                    -FingerprintHasher $fingerprintHasher
            } finally {
                $fingerprintHasher.Dispose()
            }
        }
        $documents.Add($document)

        Skip-YamlDocumentPrefix -Context $context -RequireDocumentStart
        $explicitEnd = $false
        if ($context.LineIndex -lt $lines.Count -and
            $lines[$context.LineIndex] -match '^\.\.\.(?:[ \t]|$)') {
            $explicitEnd = $true
            $endLine = $lines[$context.LineIndex]
            $endMark = New-YamlMark -Index ($lineStarts[$context.LineIndex] + 3) `
                -Line $context.LineIndex -Column 3
            if ((Get-YamlContentWithoutComment -Text $endLine.Substring(3) -Mark $endMark).
                Trim(' ', "`t").Length -gt 0) {
                throw (New-YamlException -Start $endMark -End $endMark `
                        -ErrorId 'YamlInvalidDocumentEnd' -Message (
                        'Unexpected content follows the document end marker.'
                    ))
            }
            $context.LineIndex++
            Skip-YamlDocumentPrefix -Context $context
            $implicitDocumentSeen = $false
        }
        if (-not $explicitEnd -and $context.LineIndex -lt $lines.Count -and
            $lines[$context.LineIndex] -notmatch '^---(?:[ \t]|$)' -and
            $lines[$context.LineIndex].Trim(' ', "`t").Length -gt 0) {
            $mark = New-YamlMark -Index $lineStarts[$context.LineIndex] -Line $context.LineIndex -Column 0
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidStream' -Message (
                    'Unexpected content remains after a YAML document.'
                ))
        }
    }

    return New-YamlValueBox -Value ([object[]] $documents.ToArray())
}
