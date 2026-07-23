function Read-YamlBlockScalar {
    <#
        .SYNOPSIS
        Reads a literal or folded block scalar.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [string] $Header,

        [Parameter(Mandatory)]
        [int] $HeaderColumn,

        [Parameter(Mandatory)]
        [int] $ParentIndent,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth,

        [AllowEmptyString()]
        [string] $Tag = '',

        [bool] $HasUnknownTag = $false,

        [AllowEmptyString()]
        [string] $Anchor = ''
    )

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
        if ($line -match '^(?:---|\.\.\.)(?:[ \t]|$)') {
            break
        }
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
