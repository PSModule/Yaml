function Read-YamlStreamCore {
    <#
        .SYNOPSIS
        Reads and validates all documents in a YAML stream.
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

    $parser = [YamlDotNet.Core.Parser]::new([System.IO.StringReader]::new($Yaml))
    $documents = [System.Collections.Generic.List[object]]::new()
    $context = [pscustomobject]@{
        NextId          = 1
        NodeCount       = 0
        AliasCount      = 0
        MaxDepth        = $Depth
        MaxNodes        = $MaxNodes
        MaxAliases      = $MaxAliases
        MaxScalarLength = $MaxScalarLength
        Anchors         = $null
    }

    if (-not $parser.MoveNext() -or $parser.Current -isnot [YamlDotNet.Core.Events.StreamStart]) {
        throw (New-YamlException -Start ([YamlDotNet.Core.Mark]::Empty) -End ([YamlDotNet.Core.Mark]::Empty) -ErrorId 'YamlInvalidStream' -Message (
                'The input is not a valid YAML stream.'
            ))
    }
    [void] $parser.MoveNext()

    while ($parser.Current -is [YamlDotNet.Core.Events.DocumentStart]) {
        $context.Anchors = [System.Collections.Generic.Dictionary[string, object]]::new(
            [System.StringComparer]::Ordinal
        )
        if (-not $parser.MoveNext()) {
            $emptyMark = [YamlDotNet.Core.Mark]::Empty
            $exception = New-YamlException -Start $emptyMark -End $emptyMark -ErrorId 'YamlUnexpectedEnd' -Message (
                'The YAML stream ended after a document start.'
            )
            throw $exception
        }

        $document = Read-YamlNode -Parser $parser -Context $context -Depth 1
        if ($parser.Current -isnot [YamlDotNet.Core.Events.DocumentEnd]) {
            $mark = if ($null -eq $parser.Current) { [YamlDotNet.Core.Mark]::Empty } else { $parser.Current.Start }
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidDocument' -Message (
                    'The YAML document did not end where expected.'
                ))
        }

        $fingerprintHasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            Test-YamlNodeGraph -Node $document -Visited ([System.Collections.Generic.HashSet[int]]::new()) `
                -FingerprintCache ([System.Collections.Generic.Dictionary[int, string]]::new()) `
                -FingerprintHasher $fingerprintHasher
        } finally {
            $fingerprintHasher.Dispose()
        }
        $documents.Add($document)
        [void] $parser.MoveNext()
    }

    if ($parser.Current -isnot [YamlDotNet.Core.Events.StreamEnd]) {
        $mark = if ($null -eq $parser.Current) { [YamlDotNet.Core.Mark]::Empty } else { $parser.Current.Start }
        throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidStream' -Message (
                'The YAML stream contains unexpected content.'
            ))
    }

    Write-Output -InputObject ([object[]] $documents.ToArray()) -NoEnumerate
}
