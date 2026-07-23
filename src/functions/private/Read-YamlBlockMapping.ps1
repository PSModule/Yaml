function Read-YamlBlockMapping {
    <#
        .SYNOPSIS
        Reads a block mapping, including explicit and complex keys.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [int] $Indent,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth,

        [AllowEmptyString()]
        [string] $Tag = '',

        [bool] $HasUnknownTag = $false,

        [AllowEmptyString()]
        [string] $Anchor = '',

        [AllowNull()]
        [string] $FirstText,

        [int] $FirstColumn = -1
    )

    $startLine = $Context.LineIndex
    $startColumn = if ($FirstColumn -ge 0) { $FirstColumn } else { $Indent }
    $start = New-YamlMark -Index ($Context.LineStarts[$startLine] + $startColumn) -Line $startLine `
        -Column $startColumn
    $node = New-YamlSyntaxNode -Context $Context -Kind Mapping -Depth $Depth -Start $start -End $start
    Set-YamlParsedNodeProperty -Node $node -Tag $Tag -HasUnknownTag $HasUnknownTag -Anchor $Anchor `
        -Context $Context

    $hasFirst = $PSBoundParameters.ContainsKey('FirstText')
    while ($hasFirst -or $Context.LineIndex -lt $Context.Lines.Count) {
        if ($hasFirst) {
            $content = $FirstText
            $contentColumn = $FirstColumn
            $lineNumber = $Context.LineIndex
            $hasFirst = $false
        } else {
            $lineNumber = $Context.LineIndex
            $line = $Context.Lines[$lineNumber]
            $trimmed = $line.TrimStart(' ', "`t")
            if ($line -match '^(?:---|\.\.\.)(?:[ \t]|$)') {
                break
            }
            if ($trimmed.Length -eq 0 -or $trimmed.StartsWith('#', [System.StringComparison]::Ordinal)) {
                $Context.LineIndex++
                continue
            }
            $lineIndent = Get-YamlIndent -Line $line -LineNumber $lineNumber -Context $Context
            if ($lineIndent -ne $Indent) {
                break
            }
            $content = $line.Substring($Indent)
            if ($content.StartsWith("`t", [System.StringComparison]::Ordinal)) {
                $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $Indent) `
                    -Line $lineNumber -Column $Indent
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidIndentation' -Message (
                        'A tab cannot separate indentation from a block mapping entry.'
                    ))
            }
            $contentColumn = $Indent
            if (Test-YamlIndicator -Text $content -Indicator '-') {
                break
            }
        }

        $isExplicit = Test-YamlIndicator -Text $content -Indicator '?'
        if ($isExplicit) {
            $afterQuestion = $content.Substring(1)
            $leading = $afterQuestion.Length - $afterQuestion.TrimStart().Length
            $keyText = $afterQuestion.TrimStart()
            $keyColumn = $contentColumn + 1 + $leading
            if ([string]::IsNullOrWhiteSpace((Get-YamlContentWithoutComment -Text $keyText))) {
                $Context.LineIndex++
                Skip-YamlBlockTrivia -Context $Context
                if ($Context.LineIndex -ge $Context.Lines.Count) {
                    $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $keyColumn) `
                        -Line $lineNumber -Column $keyColumn
                    $key = New-YamlEmptyScalar -Context $Context -Depth ($Depth + 1) -Mark $mark
                } else {
                    $nextIndent = Get-YamlIndent -Line $Context.Lines[$Context.LineIndex] `
                        -LineNumber $Context.LineIndex -Context $Context
                    $nextContent = $Context.Lines[$Context.LineIndex].Substring($nextIndent)
                    $indentlessSequence = $nextIndent -eq $Indent -and
                    (Test-YamlIndicator -Text $nextContent -Indicator '-')
                    if ($indentlessSequence) {
                        $key = Read-YamlBlockSequence -Context $Context -Indent $Indent -Depth ($Depth + 1)
                    } elseif ($nextIndent -gt $Indent) {
                        $key = Read-YamlBlockNode -Context $Context -ParentIndent $Indent -Depth ($Depth + 1)
                    } else {
                        $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $keyColumn) `
                            -Line $lineNumber -Column $keyColumn
                        $key = New-YamlEmptyScalar -Context $Context -Depth ($Depth + 1) -Mark $mark
                    }
                }
            } elseif (Test-YamlIndicator -Text $keyText -Indicator '-') {
                $firstItem = $keyText.Substring(1).TrimStart()
                $dashColumn = $keyColumn
                $itemColumn = $dashColumn + 1 + ($keyText.Substring(1).Length - $keyText.Substring(1).TrimStart().Length)
                $key = Read-YamlBlockSequence -Context $Context -Indent $dashColumn -Depth ($Depth + 1) `
                    -FirstItemText $firstItem -FirstItemColumn $itemColumn
            } else {
                $key = Read-YamlBlockNode -Context $Context -ParentIndent $Indent -Depth ($Depth + 1) `
                    -Segment $keyText -SegmentColumn $keyColumn -AllowIndentlessSequence
            }

            Skip-YamlBlockTrivia -Context $Context
            if ($Context.LineIndex -lt $Context.Lines.Count) {
                $valueLine = $Context.Lines[$Context.LineIndex]
                $valueIndent = Get-YamlIndent -Line $valueLine -LineNumber $Context.LineIndex -Context $Context
                $valueContent = if ($valueIndent -le $valueLine.Length) {
                    $valueLine.Substring($valueIndent)
                } else {
                    ''
                }
            } else {
                $valueIndent = -1
                $valueContent = ''
            }
            if ($valueIndent -eq $Indent -and
                (Test-YamlIndicator -Text $valueContent -Indicator ':')) {
                $valueText = $valueContent.Substring(1)
                $leading = $valueText.Length - $valueText.TrimStart().Length
                $valueText = $valueText.TrimStart()
                $valueColumn = $Indent + 1 + $leading
                if ([string]::IsNullOrWhiteSpace((Get-YamlContentWithoutComment -Text $valueText))) {
                    $valueLineNumber = $Context.LineIndex
                    $Context.LineIndex++
                    Skip-YamlBlockTrivia -Context $Context
                    if ($Context.LineIndex -lt $Context.Lines.Count) {
                        $nextLine = $Context.Lines[$Context.LineIndex]
                        $nextIndent = Get-YamlIndent -Line $nextLine -LineNumber $Context.LineIndex -Context $Context
                    } else {
                        $nextIndent = -1
                    }
                    $indentlessSequence = $nextIndent -eq $Indent -and
                    $Context.LineIndex -lt $Context.Lines.Count -and
                    (Test-YamlIndicator -Text (
                        $Context.Lines[$Context.LineIndex].Substring($nextIndent)
                    ) -Indicator '-')
                    if ($indentlessSequence) {
                        $value = Read-YamlBlockSequence -Context $Context -Indent $Indent -Depth ($Depth + 1)
                    } elseif ($nextIndent -gt $Indent) {
                        $value = Read-YamlBlockNode -Context $Context -ParentIndent $Indent `
                            -Depth ($Depth + 1) -AllowIndentlessSequence
                    } else {
                        $mark = New-YamlMark -Index ($Context.LineStarts[$valueLineNumber] + $valueColumn) `
                            -Line $valueLineNumber -Column $valueColumn
                        $value = New-YamlEmptyScalar -Context $Context -Depth ($Depth + 1) -Mark $mark
                    }
                } else {
                    $value = Read-YamlBlockNode -Context $Context -ParentIndent $Indent -Depth ($Depth + 1) `
                        -Segment $valueText -SegmentColumn $valueColumn
                }
            } else {
                $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $contentColumn) `
                    -Line $lineNumber -Column $contentColumn
                $value = New-YamlEmptyScalar -Context $Context -Depth ($Depth + 1) -Mark $mark
            }
            $node.Entries.Add([pscustomobject]@{ Key = $key; Value = $value })
            continue
        }

        $colon = Find-YamlMappingColon -Text $content
        if ($colon -lt 0) {
            $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $contentColumn) `
                -Line $lineNumber -Column $contentColumn
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidMapping' -Message (
                    'A block mapping entry is missing its value indicator.'
                ))
        }
        if ($colon -gt 1024) {
            $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $contentColumn + $colon) `
                -Line $lineNumber -Column ($contentColumn + $colon)
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidImplicitKey' -Message (
                    'An implicit mapping key cannot exceed 1024 characters.'
                ))
        }

        if ($colon -eq 0) {
            $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $contentColumn) `
                -Line $lineNumber -Column $contentColumn
            $key = New-YamlEmptyScalar -Context $Context -Depth ($Depth + 1) -Mark $mark
        } else {
            $keyText = $content.Substring(0, $colon).TrimEnd()
            $key = Read-YamlBlockKey -Context $Context -Text $keyText -Line $lineNumber `
                -Column $contentColumn -Depth ($Depth + 1)
        }

        $valueStart = $colon + 1
        $valueSource = $content.Substring($valueStart)
        $leading = $valueSource.Length - $valueSource.TrimStart().Length
        $valueText = $valueSource.TrimStart()
        $valueColumn = $contentColumn + $valueStart + $leading
        if ([string]::IsNullOrWhiteSpace((Get-YamlContentWithoutComment -Text $valueText))) {
            $Context.LineIndex = $lineNumber + 1
            Skip-YamlBlockTrivia -Context $Context
            if ($Context.LineIndex -lt $Context.Lines.Count) {
                $nextLine = $Context.Lines[$Context.LineIndex]
                $nextIndent = Get-YamlIndent -Line $nextLine -LineNumber $Context.LineIndex -Context $Context
                $nextContent = $nextLine.Substring($nextIndent)
            } else {
                $nextIndent = -1
                $nextContent = ''
            }
            $indentlessSequence = (
                $nextIndent -eq $Indent -and
                (
                    (Test-YamlIndicator -Text $nextContent -Indicator '-')
                )
            )
            if ($nextIndent -gt $Indent -or $indentlessSequence) {
                if ($indentlessSequence) {
                    $value = Read-YamlBlockSequence -Context $Context -Indent $Indent -Depth ($Depth + 1)
                } else {
                    $value = Read-YamlBlockNode -Context $Context -ParentIndent $Indent `
                        -Depth ($Depth + 1) -AllowIndentlessSequence
                }
            } else {
                $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $valueColumn) `
                    -Line $lineNumber -Column $valueColumn
                $value = New-YamlEmptyScalar -Context $Context -Depth ($Depth + 1) -Mark $mark
            }
        } else {
            if ((Test-YamlIndicator -Text $valueText -Indicator '-') -or
                (Find-YamlMappingColon -Text $valueText) -ge 0) {
                $mark = New-YamlMark -Index ($Context.LineStarts[$lineNumber] + $valueColumn) `
                    -Line $lineNumber -Column $valueColumn
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidMapping' -Message (
                        'A compact block collection cannot begin on the same line as a mapping value indicator.'
                    ))
            }
            $Context.LineIndex = $lineNumber
            $value = Read-YamlBlockNode -Context $Context -ParentIndent $Indent -Depth ($Depth + 1) `
                -Segment $valueText -SegmentColumn $valueColumn -AllowIndentlessSequence
        }
        $node.Entries.Add([pscustomobject]@{ Key = $key; Value = $value })
    }

    $endLine = [Math]::Max($startLine, $Context.LineIndex - 1)
    $node.End = New-YamlMark -Index ($Context.LineStarts[$endLine] + $Context.Lines[$endLine].Length) `
        -Line $endLine -Column $Context.Lines[$endLine].Length
    return $node
}
