function Read-YamlBlockScalar {
    <#
        .SYNOPSIS
        Reads a literal or folded block scalar.

        .DESCRIPTION
        Parses the block-scalar header, detects or applies content indentation,
        reads the scalar body, and performs YAML literal or folded chomping. The
        block node reader uses it when a `|` or `>` scalar begins a node.

        .EXAMPLE
        Read-YamlBlockScalar -Context $context -Header '|-' -HeaderColumn 4 -ParentIndent 2 -Depth 3

        Returns a scalar node containing the chomped literal block content.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # Parser context positioned at the block-scalar header line.
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        # Header text containing style, indentation, chomping, and comments.
        [Parameter(Mandatory)]
        [string] $Header,

        # Source column of the header indicator for node marks and errors.
        [Parameter(Mandatory)]
        [int] $HeaderColumn,

        # Indentation of the containing block used to detect scalar content.
        [Parameter(Mandatory)]
        [int] $ParentIndent,

        # Node depth assigned to the scalar for resource-limit enforcement.
        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth,

        # Explicit tag to attach to the scalar, when supplied.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Tag = '',

        # Preserves whether the scalar tag is unknown to the schema.
        [Parameter()]
        [bool] $HasUnknownTag = $false,

        # Anchor name to register on the scalar node, when supplied.
        [Parameter()]
        [AllowEmptyString()]
        [string] $Anchor = ''
    )

    $headerMark = New-YamlMark -Index (
        $Context.LineStarts[$Context.LineIndex] + $HeaderColumn
    ) -Line $Context.LineIndex -Column $HeaderColumn
    Assert-YamlNoByteOrderMark -Text $Header -Mark $headerMark
    if ($Header -notmatch (
            '^([|>])(?:(?:([1-9])([+-])?)|(?:([+-])([1-9])?))?' +
            '(?:[ \t]+#.*|[ \t]*)$'
        )) {
        $line = $Context.LineIndex
        $mark = New-YamlMark -Index ($Context.LineStarts[$line] + $HeaderColumn) -Line $line `
            -Column $HeaderColumn
        throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidBlockScalar' -Message (
                "The block scalar header '$Header' is malformed."
            ))
    }
    $style = $Matches[1]
    $indentDigit = if ($Matches[2]) { $Matches[2] } else { $Matches[5] }
    $chomp = if ($Matches[3]) { $Matches[3] } else { $Matches[4] }
    $startLine = $Context.LineIndex
    $start = New-YamlMark -Index ($Context.LineStarts[$startLine] + $HeaderColumn) -Line $startLine `
        -Column $HeaderColumn
    $Context.LineIndex++

    $contentIndent = if ($indentDigit) {
        [Math]::Max(0, $ParentIndent) + [int] $indentDigit
    } else {
        -1
    }
    $contentIndentDetected = -not [string]::IsNullOrEmpty($indentDigit)
    if ($contentIndent -lt 0) {
        $leadingBlankIndent = 0
        for ($probe = $Context.LineIndex; $probe -lt $Context.Lines.Count; $probe++) {
            $probeLine = $Context.Lines[$probe]
            if ($probe -eq $Context.Lines.Count - 1 -and
                $probeLine.Length -eq 0 -and
                $Context.Text.EndsWith("`n", [System.StringComparison]::Ordinal)) {
                break
            }
            $probeIndent = 0
            while ($probeIndent -lt $probeLine.Length -and $probeLine[$probeIndent] -eq ' ') {
                $probeIndent++
            }
            if ($probeLine.Trim(' ', "`t").Length -eq 0) {
                $leadingBlankIndent = [Math]::Max($leadingBlankIndent, $probeIndent)
                continue
            }
            if ($probeIndent -le $ParentIndent) {
                break
            }
            $contentIndent = $probeIndent
            $contentIndentDetected = $true
            if ($leadingBlankIndent -gt $contentIndent) {
                $mark = New-YamlMark -Index $Context.LineStarts[$probe] -Line $probe -Column 0
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidBlockScalar' -Message (
                        'Leading empty block-scalar lines cannot be more indented than the first content line.'
                    ))
            }
            break
        }
        if ($contentIndent -lt 0) {
            $contentIndent = $ParentIndent + 1
        }
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $moreIndented = [System.Collections.Generic.List[bool]]::new()
    $hasLineBreak = [System.Collections.Generic.List[bool]]::new()
    $decodedLength = 0
    while ($Context.LineIndex -lt $Context.Lines.Count) {
        $line = $Context.Lines[$Context.LineIndex]
        if ($line -match '^(?:---|\.\.\.)(?:[ \t]|$)' -or
            (Test-YamlDocumentByteOrderMark -Context $Context -RequireDocumentStart)) {
            break
        }
        Assert-YamlNoByteOrderMark -Text $line -Mark $start
        if ($Context.LineIndex -eq $Context.Lines.Count - 1 -and
            $line.Length -eq 0 -and
            $Context.Text.EndsWith("`n", [System.StringComparison]::Ordinal)) {
            break
        }
        $lineBreak = $Context.LineIndex -lt $Context.Lines.Count - 1
        $indent = 0
        while ($indent -lt $line.Length -and $line[$indent] -eq ' ') {
            $indent++
        }
        if ($line.Trim(' ', "`t").Length -eq 0) {
            if ($indent -lt $line.Length -and $line[$indent] -eq "`t" -and
                $indent -lt $contentIndent) {
                $mark = New-YamlMark -Index ($Context.LineStarts[$Context.LineIndex] + $indent) `
                    -Line $Context.LineIndex -Column $indent
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidIndentation' -Message (
                        'A tab cannot provide block-scalar indentation.'
                    ))
            }
            $blankContent = if ($contentIndentDetected) {
                if ($line.Length -ge $contentIndent) {
                    $line.Substring($contentIndent)
                } else {
                    ''
                }
            } else {
                $line.Substring($indent)
            }
            if ($decodedLength + $blankContent.Length + [int] $lineBreak -gt
                $Context.MaxScalarLength) {
                throw (New-YamlException -Start $start -End $start -ErrorId 'YamlScalarLimitExceeded' -Message (
                        "A YAML scalar exceeds the configured limit of $($Context.MaxScalarLength) characters."
                    ))
            }
            $lines.Add($blankContent)
            $moreIndented.Add($blankContent.Length -gt 0)
            $hasLineBreak.Add($lineBreak)
            $decodedLength += $blankContent.Length + [int] $lineBreak
            $Context.LineIndex++
            continue
        }
        if ($indent -lt $contentIndent) {
            break
        }
        $contentLength = $line.Length - $contentIndent
        if ($decodedLength + $contentLength + [int] $lineBreak -gt $Context.MaxScalarLength) {
            throw (New-YamlException -Start $start -End $start -ErrorId 'YamlScalarLimitExceeded' -Message (
                    "A YAML scalar exceeds the configured limit of $($Context.MaxScalarLength) characters."
                ))
        }
        $lines.Add($line.Substring($contentIndent, $contentLength))
        $moreIndented.Add(
            $contentLength -gt 0 -and $line[$contentIndent] -in @(' ', "`t")
        )
        $hasLineBreak.Add($lineBreak)
        $decodedLength += $contentLength + [int] $lineBreak
        $Context.LineIndex++
    }

    $builder = [System.Text.StringBuilder]::new()
    for ($index = 0; $index -lt $lines.Count; $index++) {
        [void] $builder.Append($lines[$index])
        if (-not $hasLineBreak[$index]) {
            continue
        }
        if ($style -eq '|') {
            [void] $builder.Append("`n")
            continue
        }
        if ($index -eq $lines.Count - 1) {
            [void] $builder.Append("`n")
            continue
        }
        $currentBlank = $lines[$index].Length -eq 0
        $nextBlank = $lines[$index + 1].Length -eq 0
        if ($currentBlank -or $moreIndented[$index] -or $moreIndented[$index + 1]) {
            [void] $builder.Append("`n")
        } elseif (-not $nextBlank) {
            [void] $builder.Append(' ')
        } else {
            $lookAhead = $index + 1
            while ($lookAhead -lt $lines.Count -and $lines[$lookAhead].Length -eq 0) {
                $lookAhead++
            }
            if ($lookAhead -lt $lines.Count -and $moreIndented[$lookAhead]) {
                [void] $builder.Append("`n")
            }
        }
    }
    $value = $builder.ToString()
    if ($chomp -eq '+' -and $lines.Count -gt 0 -and
        -not $hasLineBreak[$lines.Count - 1] -and
        $lines[$lines.Count - 1].Length -eq 0) {
        $value += "`n"
    }
    if ($chomp -eq '+' -and $style -eq '>') {
        # Rule 182 splits folded content into l-nb-diff-lines b-chomped-last l-chomped-empty.
        # Folding emits nothing for the break that closes the last non-empty line unless that
        # line or the next one is more indented, so the b-chomped-last feed has to be added
        # back in the plain-fold case whenever trailing empty lines are kept.
        $lastContentIndex = -1
        for ($index = $lines.Count - 1; $index -ge 0; $index--) {
            if ($lines[$index].Length -gt 0) {
                $lastContentIndex = $index
                break
            }
        }
        if ($lastContentIndex -ge 0 -and $lastContentIndex -lt $lines.Count - 1 -and
            -not $moreIndented[$lastContentIndex] -and
            -not $moreIndented[$lastContentIndex + 1]) {
            $value += "`n"
        }
    }
    if ($chomp -eq '-') {
        $value = $value.TrimEnd("`n")
    } elseif ($chomp -ne '+') {
        $value = $value.TrimEnd("`n")
        $hasContent = $false
        foreach ($contentLine in $lines) {
            if ($contentLine.Length -gt 0) {
                $hasContent = $true
                break
            }
        }
        if ($hasContent) {
            $value += "`n"
        }
    }
    $endLine = [Math]::Max($startLine, $Context.LineIndex - 1)
    $end = New-YamlMark -Index ($Context.LineStarts[$endLine] + $Context.Lines[$endLine].Length) `
        -Line $endLine -Column $Context.Lines[$endLine].Length
    $node = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth $Depth -Start $start -End $end
    Set-YamlParsedNodeProperty -Node $node -Tag $Tag -HasUnknownTag $HasUnknownTag -Anchor $Anchor `
        -Context $Context
    $node.Value = $value
    $node.Style = if ($style -eq '|') { 'Literal' } else { 'Folded' }
    $node.IsQuotedImplicit = [string]::IsNullOrEmpty($Tag) -and -not $HasUnknownTag
    return $node
}
