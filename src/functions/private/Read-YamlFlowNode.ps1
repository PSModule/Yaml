function Read-YamlFlowNode {
    <#
        .SYNOPSIS
        Reads one node from a character cursor, including flow collections.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Cursor,

        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [ValidateRange(1, 2147483647)]
        [int] $Depth,

        [AllowEmptyString()]
        [string] $PendingTag = '',

        [bool] $PendingUnknownTag = $false,

        [AllowEmptyString()]
        [string] $PendingAnchor = '',

        [switch] $InFlowCollection
    )

    Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
    $start = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
    $tag = $PendingTag
    $unknownTag = $PendingUnknownTag
    $anchor = $PendingAnchor

    while ($Cursor.Index -lt $Context.Text.Length) {
        $character = $Context.Text[$Cursor.Index]
        if ($character -eq '!') {
            if (-not [string]::IsNullOrEmpty($tag) -or $unknownTag) {
                throw (New-YamlException -Start $start -End $start -ErrorId 'YamlDuplicateNodeProperty' -Message (
                        'A YAML node cannot have more than one tag property.'
                    ))
            }
            $tokenStart = $Cursor.Index
            if ($Cursor.Index + 1 -lt $Context.Text.Length -and $Context.Text[$Cursor.Index + 1] -eq '<') {
                while ($Cursor.Index -lt $Context.Text.Length -and $Context.Text[$Cursor.Index] -ne '>') {
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                }
                if ($Cursor.Index -ge $Context.Text.Length) {
                    throw (New-YamlException -Start $start -End $start -ErrorId 'YamlInvalidTag' -Message (
                            'A verbatim YAML tag is missing its closing angle bracket.'
                        ))
                }
                Move-YamlCursor -Cursor $Cursor -Context $Context
            } else {
                while ($Cursor.Index -lt $Context.Text.Length -and
                    -not (Test-YamlWhiteSpace -Character $Context.Text[$Cursor.Index]) -and
                    $Context.Text[$Cursor.Index] -cne "`n" -and
                    $Context.Text[$Cursor.Index] -notin @(',', '[', ']', '{', '}')) {
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                }
            }
            if ($Cursor.Index - $tokenStart -gt $Context.MaxTagLength) {
                throw (New-YamlException -Start $start -End $start -ErrorId 'YamlTagLimitExceeded' -Message (
                        "A YAML tag token exceeds the configured limit of $($Context.MaxTagLength) characters."
                    ))
            }
            $resolved = Resolve-YamlTag -Token $Context.Text.Substring(
                $tokenStart, $Cursor.Index - $tokenStart
            ) -Context $Context -Mark $start
            $tag = $resolved.Tag
            $unknownTag = $resolved.IsUnknown
            Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
            continue
        }
        if ($character -eq '&') {
            if (-not [string]::IsNullOrEmpty($anchor)) {
                throw (New-YamlException -Start $start -End $start -ErrorId 'YamlDuplicateNodeProperty' -Message (
                        'A YAML node cannot have more than one anchor property.'
                    ))
            }
            Move-YamlCursor -Cursor $Cursor -Context $Context
            $anchorStart = $Cursor.Index
            while ($Cursor.Index -lt $Context.Text.Length -and
                -not (Test-YamlWhiteSpace -Character $Context.Text[$Cursor.Index]) -and
                $Context.Text[$Cursor.Index] -cne "`n" -and
                $Context.Text[$Cursor.Index] -notin @(',', '[', ']', '{', '}') -and
                -not ($InFlowCollection -and
                    (Test-YamlMappingValueIndicator -Text $Context.Text -Index $Cursor.Index -Flow))) {
                Move-YamlCursor -Cursor $Cursor -Context $Context
            }
            $anchor = $Context.Text.Substring($anchorStart, $Cursor.Index - $anchorStart)
            Assert-YamlNoByteOrderMark -Text $anchor -Mark $start
            if ([string]::IsNullOrEmpty($anchor)) {
                throw (New-YamlException -Start $start -End $start -ErrorId 'YamlInvalidAnchor' -Message (
                        'A YAML anchor name is missing.'
                    ))
            }
            Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
            continue
        }
        break
    }

    if ($Cursor.Index -ge $Context.Text.Length) {
        throw (New-YamlException -Start $start -End $start -ErrorId 'YamlUnexpectedEnd' -Message (
                'The YAML stream ended while a node was expected.'
            ))
    }

    $character = $Context.Text[$Cursor.Index]
    if ($character -in @(':', ',', ']', '}') -and (
            -not [string]::IsNullOrEmpty($tag) -or $unknownTag -or
            -not [string]::IsNullOrEmpty($anchor)
        )) {
        $node = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth $Depth -Start $start -End $start
        Set-YamlParsedNodeProperty -Node $node -Tag $tag -HasUnknownTag $unknownTag -Anchor $anchor `
            -Context $Context
        $node.Value = ''
        $node.IsPlainImplicit = [string]::IsNullOrEmpty($tag) -and -not $unknownTag
        return $node
    }
    if ($character -eq '*') {
        if (-not [string]::IsNullOrEmpty($tag) -or $unknownTag -or
            -not [string]::IsNullOrEmpty($anchor)) {
            throw (New-YamlException -Start $start -End $start -ErrorId 'YamlInvalidAlias' -Message (
                    'A YAML alias node cannot have tag or anchor properties.'
                ))
        }
        Move-YamlCursor -Cursor $Cursor -Context $Context
        $aliasStart = $Cursor.Index
        while ($Cursor.Index -lt $Context.Text.Length -and
            -not (Test-YamlWhiteSpace -Character $Context.Text[$Cursor.Index]) -and
            $Context.Text[$Cursor.Index] -cne "`n" -and
            $Context.Text[$Cursor.Index] -notin @(',', '[', ']', '{', '}') -and
            -not ($InFlowCollection -and
                (Test-YamlMappingValueIndicator -Text $Context.Text -Index $Cursor.Index -Flow))) {
            Move-YamlCursor -Cursor $Cursor -Context $Context
        }
        $alias = $Context.Text.Substring($aliasStart, $Cursor.Index - $aliasStart)
        Assert-YamlNoByteOrderMark -Text $alias -Mark $start
        $Context.AliasCount++
        if ($Context.AliasCount -gt $Context.MaxAliases) {
            throw (New-YamlException -Start $start -End $start -ErrorId 'YamlAliasLimitExceeded' -Message (
                    "The YAML stream exceeds the configured limit of $($Context.MaxAliases) aliases."
                ))
        }
        if (-not $Context.Anchors.ContainsKey($alias)) {
            throw (New-YamlException -Start $start -End $start -ErrorId 'YamlUndefinedAlias' -Message (
                    "The YAML alias '*$alias' does not refer to a preceding anchor."
                ))
        }
        $end = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
        $node = New-YamlSyntaxNode -Context $Context -Kind Alias -Depth $Depth -Start $start -End $end
        $node.Target = $Context.Anchors[$alias]
        return $node
    }

    if ($character -eq '[' -or $character -eq '{') {
        $kind = if ($character -eq '[') { 'Sequence' } else { 'Mapping' }
        $closing = if ($character -eq '[') { ']' } else { '}' }
        $node = New-YamlSyntaxNode -Context $Context -Kind $kind -Depth $Depth -Start $start -End $start
        Set-YamlParsedNodeProperty -Node $node -Tag $tag -HasUnknownTag $unknownTag -Anchor $anchor `
            -Context $Context
        Move-YamlCursor -Cursor $Cursor -Context $Context
        Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context

        if ($kind -eq 'Sequence') {
            while ($Cursor.Index -lt $Context.Text.Length -and $Context.Text[$Cursor.Index] -ne $closing) {
                $explicitPair = $false
                if ($Context.Text[$Cursor.Index] -eq '?' -and
                    ($Cursor.Index + 1 -ge $Context.Text.Length -or
                    (Test-YamlWhiteSpace -Character $Context.Text[$Cursor.Index + 1]) -or
                    $Context.Text[$Cursor.Index + 1] -ceq "`n")) {
                    $explicitPair = $true
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                    Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
                }
                if ($Cursor.Index -lt $Context.Text.Length -and
                    (Test-YamlMappingValueIndicator -Text $Context.Text -Index $Cursor.Index -Flow)) {
                    $itemMark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                    $item = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth ($Depth + 1) `
                        -Start $itemMark -End $itemMark
                    $item.Value = ''
                    $item.IsPlainImplicit = $true
                } else {
                    $item = Read-YamlFlowNode -Cursor $Cursor -Context $Context -Depth ($Depth + 1) `
                        -InFlowCollection
                }
                $itemStartLine = $item.Start.Line
                Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
                if ($Cursor.Index -lt $Context.Text.Length -and $Context.Text[$Cursor.Index] -eq ':') {
                    if (-not $explicitPair -and (
                            $Cursor.Line -ne $itemStartLine -or
                            (Get-YamlImplicitKeyLength -Node $item -Context $Context) -gt 1024
                        )) {
                        $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                        throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidImplicitKey' -Message (
                                'An implicit mapping key must fit on one line and cannot exceed 1024 Unicode scalar values.'
                            ))
                    }
                    $pair = New-YamlSyntaxNode -Context $Context -Kind Mapping -Depth ($Depth + 1) `
                        -Start $item.Start -End $item.End
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                    Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
                    if ($Cursor.Index -ge $Context.Text.Length -or
                        $Context.Text[$Cursor.Index] -in @(',', ']')) {
                        $nullMark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                        $value = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth ($Depth + 2) `
                            -Start $nullMark -End $nullMark
                        $value.Value = ''
                        $value.IsPlainImplicit = $true
                    } else {
                        $value = Read-YamlFlowNode -Cursor $Cursor -Context $Context -Depth ($Depth + 2) `
                            -InFlowCollection
                    }
                    $pair.Entries.Add([pscustomobject]@{ Key = $item; Value = $value })
                    $item = $pair
                } elseif ($explicitPair) {
                    $pair = New-YamlSyntaxNode -Context $Context -Kind Mapping -Depth ($Depth + 1) `
                        -Start $item.Start -End $item.End
                    $nullMark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                    $value = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth ($Depth + 2) `
                        -Start $nullMark -End $nullMark
                    $value.Value = ''
                    $value.IsPlainImplicit = $true
                    $pair.Entries.Add([pscustomobject]@{ Key = $item; Value = $value })
                    $item = $pair
                }
                $node.Items.Add($item)
                Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
                if ($Cursor.Index -lt $Context.Text.Length -and $Context.Text[$Cursor.Index] -eq ',') {
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                    Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
                    continue
                }
                if ($Cursor.Index -ge $Context.Text.Length -or $Context.Text[$Cursor.Index] -ne $closing) {
                    $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                    throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidFlowCollection' -Message (
                            "A flow sequence requires ',' or '$closing'."
                        ))
                }
            }
        } else {
            while ($Cursor.Index -lt $Context.Text.Length -and $Context.Text[$Cursor.Index] -ne $closing) {
                $explicit = $false
                if ($Context.Text[$Cursor.Index] -eq '?' -and
                    ($Cursor.Index + 1 -ge $Context.Text.Length -or
                    (Test-YamlWhiteSpace -Character $Context.Text[$Cursor.Index + 1]) -or
                    $Context.Text[$Cursor.Index + 1] -ceq "`n")) {
                    $explicit = $true
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                    Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
                }
                if ($Context.Text[$Cursor.Index] -eq ':') {
                    $nullMark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                    $key = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth ($Depth + 1) `
                        -Start $nullMark -End $nullMark
                    $key.Value = ''
                    $key.IsPlainImplicit = $true
                } else {
                    if ($explicit -and $Context.Text[$Cursor.Index] -in @(',', '}')) {
                        $nullMark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                        $key = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth ($Depth + 1) `
                            -Start $nullMark -End $nullMark
                        $key.Value = ''
                        $key.IsPlainImplicit = $true
                    } else {
                        $key = Read-YamlFlowNode -Cursor $Cursor -Context $Context -Depth ($Depth + 1) `
                            -InFlowCollection
                    }
                }
                Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
                if (-not $explicit -and (
                        (Get-YamlImplicitKeyLength -Node $key -Context $Context) -gt 1024
                    )) {
                    $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                    throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidImplicitKey' -Message (
                            'An implicit mapping key must fit on one line and cannot exceed 1024 Unicode scalar values.'
                        ))
                }
                if ($Cursor.Index -ge $Context.Text.Length -or $Context.Text[$Cursor.Index] -ne ':') {
                    if (-not $explicit) {
                        if ($Cursor.Index -lt $Context.Text.Length -and
                            $Context.Text[$Cursor.Index] -in @(',', '}')) {
                            $nullMark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                            $value = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth ($Depth + 1) `
                                -Start $nullMark -End $nullMark
                            $value.Value = ''
                            $value.IsPlainImplicit = $true
                        } else {
                            $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidFlowMapping' -Message (
                                    'A flow mapping entry is missing its value indicator.'
                                ))
                        }
                    } else {
                        $nullMark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                        $value = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth ($Depth + 1) `
                            -Start $nullMark -End $nullMark
                        $value.Value = ''
                        $value.IsPlainImplicit = $true
                    }
                } else {
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                    Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
                    if ($Cursor.Index -ge $Context.Text.Length -or
                        $Context.Text[$Cursor.Index] -in @(',', '}')) {
                        $nullMark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                        $value = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth ($Depth + 1) `
                            -Start $nullMark -End $nullMark
                        $value.Value = ''
                        $value.IsPlainImplicit = $true
                    } else {
                        $value = Read-YamlFlowNode -Cursor $Cursor -Context $Context -Depth ($Depth + 1) `
                            -InFlowCollection
                    }
                }
                $node.Entries.Add([pscustomobject]@{ Key = $key; Value = $value })
                Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
                if ($Cursor.Index -lt $Context.Text.Length -and $Context.Text[$Cursor.Index] -eq ',') {
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                    Skip-YamlFlowTrivia -Cursor $Cursor -Context $Context
                    continue
                }
                if ($Cursor.Index -ge $Context.Text.Length -or $Context.Text[$Cursor.Index] -ne $closing) {
                    $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                    throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidFlowCollection' -Message (
                            "A flow mapping requires ',' or '$closing'."
                        ))
                }
            }
        }

        if ($Cursor.Index -ge $Context.Text.Length) {
            throw (New-YamlException -Start $start -End $start -ErrorId 'YamlUnexpectedEnd' -Message (
                    "A flow collection is missing '$closing'."
                ))
        }
        Move-YamlCursor -Cursor $Cursor -Context $Context
        $node.End = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
        return $node
    }

    if ($character -eq "'" -or $character -eq '"') {
        $quote = $character
        Move-YamlCursor -Cursor $Cursor -Context $Context
        $builder = [System.Text.StringBuilder]::new()
        $closed = $false
        $pendingBreaks = 0
        $rawTrailingWhitespace = 0
        while ($Cursor.Index -lt $Context.Text.Length) {
            $character = $Context.Text[$Cursor.Index]
            if ($character -eq $quote) {
                if ($quote -eq "'" -and $Cursor.Index + 1 -lt $Context.Text.Length -and
                    $Context.Text[$Cursor.Index + 1] -eq "'") {
                    if ($pendingBreaks -gt 0) {
                        [void] $builder.Append(
                            $(if ($pendingBreaks -eq 1) { ' ' } else { "`n" * ($pendingBreaks - 1) })
                        )
                    }
                    $pendingBreaks = 0
                    [void] $builder.Append("'")
                    $rawTrailingWhitespace = 0
                    Move-YamlCursor -Cursor $Cursor -Context $Context -Count 2
                    continue
                }
                if ($pendingBreaks -gt 0) {
                    [void] $builder.Append(
                        $(if ($pendingBreaks -eq 1) { ' ' } else { "`n" * ($pendingBreaks - 1) })
                    )
                    $pendingBreaks = 0
                }
                Move-YamlCursor -Cursor $Cursor -Context $Context
                $closed = $true
                break
            }
            if ($quote -eq '"' -and $character -eq '\') {
                Move-YamlCursor -Cursor $Cursor -Context $Context
                if ($Cursor.Index -ge $Context.Text.Length) {
                    break
                }
                $escape = $Context.Text[$Cursor.Index]
                if ($escape -eq "`n") {
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                    while ($Cursor.Index -lt $Context.Text.Length -and
                        $Context.Text[$Cursor.Index] -in @(' ', "`t")) {
                        Move-YamlCursor -Cursor $Cursor -Context $Context
                    }
                    continue
                }
                $simpleEscape = $true
                $escapedCharacter = switch -CaseSensitive ([string] $escape) {
                    '0' { [char] 0 } 'a' { [char] 7 } 'b' { [char] 8 } 't' { [char] 9 }
                    'n' { [char] 10 } 'v' { [char] 11 } 'f' { [char] 12 } 'r' { [char] 13 }
                    'e' { [char] 27 } ' ' { [char] 32 } '"' { [char] 34 } '/' { [char] 47 }
                    '\' { [char] 92 } 'N' { [char] 0x85 } '_' { [char] 0xA0 }
                    'L' { [char] 0x2028 } 'P' { [char] 0x2029 }
                    "`t" { [char] 9 }
                    default { $simpleEscape = $false; $null }
                }
                if ($simpleEscape) {
                    if ($pendingBreaks -gt 0) {
                        [void] $builder.Append(
                            $(if ($pendingBreaks -eq 1) { ' ' } else { "`n" * ($pendingBreaks - 1) })
                        )
                    }
                    $pendingBreaks = 0
                    [void] $builder.Append($escapedCharacter)
                    $rawTrailingWhitespace = 0
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                    continue
                }
                $hexLength = switch -CaseSensitive ([string] $escape) {
                    'x' { 2 }
                    'u' { 4 }
                    'U' { 8 }
                    default { 0 }
                }
                if ($hexLength -eq 0 -or $Cursor.Index + $hexLength -ge $Context.Text.Length) {
                    $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                    throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidEscape' -Message (
                            "The YAML escape sequence '\\$escape' is invalid."
                        ))
                }
                $hex = $Context.Text.Substring($Cursor.Index + 1, $hexLength)
                [uint32] $codePoint = 0
                if (-not [uint32]::TryParse(
                        $hex,
                        [System.Globalization.NumberStyles]::HexNumber,
                        [System.Globalization.CultureInfo]::InvariantCulture,
                        [ref] $codePoint
                    ) -or $codePoint -gt 0x10FFFF -or
                    ($codePoint -ge 0xD800 -and $codePoint -le 0xDFFF)) {
                    $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                    throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidEscape' -Message (
                            "The YAML escape sequence '\\$escape$hex' is invalid."
                        ))
                }
                if ($pendingBreaks -gt 0) {
                    [void] $builder.Append(
                        $(if ($pendingBreaks -eq 1) { ' ' } else { "`n" * ($pendingBreaks - 1) })
                    )
                }
                $pendingBreaks = 0
                [void] $builder.Append([char]::ConvertFromUtf32([int] $codePoint))
                $rawTrailingWhitespace = 0
                Move-YamlCursor -Cursor $Cursor -Context $Context -Count ($hexLength + 1)
                continue
            }
            if ($character -eq "`n") {
                if ($rawTrailingWhitespace -gt 0) {
                    $builder.Length -= $rawTrailingWhitespace
                }
                $rawTrailingWhitespace = 0
                $pendingBreaks = 0
                while ($Cursor.Index -lt $Context.Text.Length -and
                    $Context.Text[$Cursor.Index] -eq "`n") {
                    $pendingBreaks++
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                    $indentSpaces = 0
                    while ($Cursor.Index -lt $Context.Text.Length -and
                        $Context.Text[$Cursor.Index] -in @(' ', "`t")) {
                        if ($Context.Text[$Cursor.Index] -eq ' ') {
                            $indentSpaces++
                        }
                        Move-YamlCursor -Cursor $Cursor -Context $Context
                    }
                }
                if ($Cursor.Index -lt $Context.Text.Length -and
                    $Context.Text[$Cursor.Index] -ne "`n" -and
                    $indentSpaces -le $Cursor.ParentIndent) {
                    $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                    throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidIndentation' -Message (
                            'A multiline quoted scalar must be indented beyond its surrounding block context.'
                        ))
                }
                if ($Cursor.Column -eq 0 -and $Cursor.Index + 3 -le $Context.Text.Length) {
                    $marker = $Context.Text.Substring($Cursor.Index, 3)
                    if ($marker -cin @('---', '...') -and
                        ($Cursor.Index + 3 -eq $Context.Text.Length -or
                        (Test-YamlWhiteSpace -Character $Context.Text[$Cursor.Index + 3]) -or
                        $Context.Text[$Cursor.Index + 3] -ceq "`n")) {
                        $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column 0
                        throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidQuotedScalar' -Message (
                                'A document marker cannot occur inside a multiline quoted scalar.'
                            ))
                    }
                }
                continue
            }
            if ($pendingBreaks -gt 0) {
                [void] $builder.Append(
                    $(if ($pendingBreaks -eq 1) { ' ' } else { "`n" * ($pendingBreaks - 1) })
                )
            }
            $pendingBreaks = 0
            [void] $builder.Append($character)
            if ($character -in @(' ', "`t")) {
                $rawTrailingWhitespace++
            } else {
                $rawTrailingWhitespace = 0
            }
            if ($builder.Length -gt $Context.MaxScalarLength) {
                throw (New-YamlException -Start $start -End $start -ErrorId 'YamlScalarLimitExceeded' -Message (
                        "A YAML scalar exceeds the configured limit of $($Context.MaxScalarLength) characters."
                    ))
            }
            Move-YamlCursor -Cursor $Cursor -Context $Context
        }
        if (-not $closed) {
            throw (New-YamlException -Start $start -End $start -ErrorId 'YamlUnexpectedEnd' -Message (
                    'A quoted YAML scalar is missing its closing quote.'
                ))
        }
        $end = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
        $node = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth $Depth -Start $start -End $end
        Set-YamlParsedNodeProperty -Node $node -Tag $tag -HasUnknownTag $unknownTag -Anchor $anchor `
            -Context $Context
        $node.Value = $builder.ToString()
        $node.Style = if ($quote -eq "'") { 'SingleQuoted' } else { 'DoubleQuoted' }
        $node.IsQuotedImplicit = [string]::IsNullOrEmpty($tag) -and -not $unknownTag
        if ($node.Value.Length -gt $Context.MaxScalarLength) {
            throw (New-YamlException -Start $start -End $end -ErrorId 'YamlScalarLimitExceeded' -Message (
                    "A YAML scalar exceeds the configured limit of $($Context.MaxScalarLength) characters."
                ))
        }
        return $node
    }

    $builder = [System.Text.StringBuilder]::new()
    $pendingWhiteSpace = [System.Text.StringBuilder]::new()
    $pendingBreaks = 0
    $lastContentLine = $Cursor.Line
    $firstPlainCharacter = $Context.Text[$Cursor.Index]
    if ($firstPlainCharacter -in @(',', '[', ']', '{', '}', '#', '&', '*', '!', '|', '>', "'", '"', '%', '@', '`') -or
        ($firstPlainCharacter -in @('-', '?', ':') -and (
            $Cursor.Index + 1 -ge $Context.Text.Length -or
            (Test-YamlWhiteSpace -Character $Context.Text[$Cursor.Index + 1]) -or
            $Context.Text[$Cursor.Index + 1] -ceq "`n" -or
            $Context.Text[$Cursor.Index + 1] -in @(',', '[', ']', '{', '}')
        ))) {
        throw (New-YamlException -Start $start -End $start -ErrorId 'YamlInvalidPlainScalar' -Message (
                'The first character is not allowed in a YAML plain scalar.'
            ))
    }
    while ($Cursor.Index -lt $Context.Text.Length) {
        $character = $Context.Text[$Cursor.Index]
        if ($character -ceq [char] 0xFEFF) {
            $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
            throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidByteOrderMark' -Message (
                    'A raw YAML byte order mark is only allowed in a quoted scalar or document prefix.'
                ))
        }
        if ($character -in @(',', '[', ']', '{', '}')) {
            break
        }
        if ($InFlowCollection -and
            (Test-YamlMappingValueIndicator -Text $Context.Text -Index $Cursor.Index -Flow)) {
            break
        }
        if ($character -eq '#' -and
            ($Cursor.Index -eq 0 -or
            (Test-YamlWhiteSpace -Character $Context.Text[$Cursor.Index - 1]) -or
            $Context.Text[$Cursor.Index - 1] -ceq "`n")) {
            break
        }
        if (Test-YamlWhiteSpace -Character $character) {
            [void] $pendingWhiteSpace.Append($character)
            Move-YamlCursor -Cursor $Cursor -Context $Context
            continue
        }
        if ($character -eq "`n") {
            $null = $pendingWhiteSpace.Clear()
            $pendingBreaks = 0
            while ($Cursor.Index -lt $Context.Text.Length -and
                $Context.Text[$Cursor.Index] -ceq "`n") {
                $pendingBreaks++
                Move-YamlCursor -Cursor $Cursor -Context $Context
                $indentSpaces = 0
                while ($Cursor.Index -lt $Context.Text.Length -and
                    $Context.Text[$Cursor.Index] -ceq ' ') {
                    $indentSpaces++
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                }
                while ($Cursor.Index -lt $Context.Text.Length -and
                    $Context.Text[$Cursor.Index] -ceq "`t") {
                    Move-YamlCursor -Cursor $Cursor -Context $Context
                }
            }
            if ($Cursor.Index -lt $Context.Text.Length -and
                $Context.Text[$Cursor.Index] -notin @("`n", '#', ']', '}') -and
                $indentSpaces -le $Cursor.ParentIndent) {
                $mark = New-YamlMark -Index $Cursor.Index -Line $Cursor.Line -Column $Cursor.Column
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidFlowIndentation' -Message (
                        'A multiline flow scalar must be indented beyond its surrounding block context.'
                    ))
            }
            continue
        }
        if ($pendingBreaks -gt 0 -and $builder.Length -gt 0) {
            [void] $builder.Append(
                $(if ($pendingBreaks -eq 1) { ' ' } else { "`n" * ($pendingBreaks - 1) })
            )
        } elseif ($pendingWhiteSpace.Length -gt 0 -and $builder.Length -gt 0) {
            [void] $builder.Append($pendingWhiteSpace)
        }
        $pendingBreaks = 0
        $null = $pendingWhiteSpace.Clear()
        [void] $builder.Append($character)
        if ($builder.Length -gt $Context.MaxScalarLength) {
            throw (New-YamlException -Start $start -End $start -ErrorId 'YamlScalarLimitExceeded' -Message (
                    "A YAML scalar exceeds the configured limit of $($Context.MaxScalarLength) characters."
                ))
        }
        $lastContentLine = $Cursor.Line
        Move-YamlCursor -Cursor $Cursor -Context $Context
    }
    $value = $builder.ToString().TrimEnd(' ', "`t")
    if ([string]::IsNullOrEmpty($value)) {
        throw (New-YamlException -Start $start -End $start -ErrorId 'YamlExpectedNode' -Message (
                'A YAML node was expected.'
            ))
    }
    $end = New-YamlMark -Index $Cursor.Index -Line $lastContentLine -Column $Cursor.Column
    $node = New-YamlSyntaxNode -Context $Context -Kind Scalar -Depth $Depth -Start $start -End $end
    Set-YamlParsedNodeProperty -Node $node -Tag $tag -HasUnknownTag $unknownTag -Anchor $anchor `
        -Context $Context
    $node.Value = $value
    $node.Style = 'Plain'
    $node.IsPlainImplicit = [string]::IsNullOrEmpty($tag) -and -not $unknownTag
    if ($value.Length -gt $Context.MaxScalarLength) {
        throw (New-YamlException -Start $start -End $end -ErrorId 'YamlScalarLimitExceeded' -Message (
                "A YAML scalar exceeds the configured limit of $($Context.MaxScalarLength) characters."
            ))
    }
    return $node
}
