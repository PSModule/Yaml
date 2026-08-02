function Read-YamlNodeProperty {
    <#
        .SYNOPSIS
        Reads tag and anchor properties from the start of a node segment.

        .DESCRIPTION
        Scans leading YAML node properties, resolves tag handles through the
        current directive context, and returns the unconsumed node text. Block
        node readers use the result before choosing the concrete node kind.

        .EXAMPLE
        Read-YamlNodeProperty -Text '!<tag:example.com,2026:thing> &item value' -Line 0 -Column 0 -Context $context

        Returns the resolved tag, anchor name, remaining text, and consumed width.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        # Node segment whose leading tag and anchor properties are scanned.
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        # Source line used to locate property errors precisely.
        [Parameter(Mandatory)]
        [int] $Line,

        # Source column where the segment starts for mark calculation.
        [Parameter(Mandatory)]
        [int] $Column,

        # Parser context that supplies tag handles, limits, and source offsets.
        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $position = 0
    $tag = ''
    $unknown = $false
    $anchor = ''
    while ($position -lt $Text.Length) {
        while ($position -lt $Text.Length -and
            (Test-YamlWhiteSpace -Character $Text[$position])) {
            $position++
        }
        if ($position -ge $Text.Length) {
            break
        }
        if ($Text[$position] -eq '!') {
            if (-not [string]::IsNullOrEmpty($tag) -or $unknown) {
                $mark = New-YamlMark -Index ($Context.LineStarts[$Line] + $Column + $position) -Line $Line `
                    -Column ($Column + $position)
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlDuplicateNodeProperty' -Message (
                        'A YAML node cannot have more than one tag property.'
                    ))
            }
            $start = $position
            if ($position + 1 -lt $Text.Length -and $Text[$position + 1] -eq '<') {
                $end = $Text.IndexOf('>', $position + 2)
                if ($end -lt 0) {
                    $end = $Text.Length - 1
                }
                $position = $end + 1
            } else {
                while ($position -lt $Text.Length -and
                    -not (Test-YamlWhiteSpace -Character $Text[$position]) -and
                    $Text[$position] -notin @(',', '[', ']', '{', '}')) {
                    $position++
                }
            }
            if ($position - $start -gt (
                    Get-YamlTagPresentationLimit -Context $Context -Token
                )) {
                $mark = New-YamlMark -Index ($Context.LineStarts[$Line] + $Column + $start) -Line $Line `
                    -Column ($Column + $start)
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlTagLimitExceeded' -Message (
                        "A YAML tag token cannot fit the configured limit of $($Context.MaxTagLength) decoded characters."
                    ))
            }
            $token = $Text.Substring($start, $position - $start)
            $mark = New-YamlMark -Index ($Context.LineStarts[$Line] + $Column + $start) -Line $Line `
                -Column ($Column + $start)
            $resolved = Resolve-YamlTag -Token $token -Context $Context -Mark $mark
            $tag = $resolved.Tag
            $unknown = $resolved.IsUnknown
            continue
        }
        if ($Text[$position] -eq '&') {
            if (-not [string]::IsNullOrEmpty($anchor)) {
                $mark = New-YamlMark -Index ($Context.LineStarts[$Line] + $Column + $position) -Line $Line `
                    -Column ($Column + $position)
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlDuplicateNodeProperty' -Message (
                        'A YAML node cannot have more than one anchor property.'
                    ))
            }
            $start = ++$position
            while ($position -lt $Text.Length -and
                -not (Test-YamlWhiteSpace -Character $Text[$position]) -and
                $Text[$position] -notin @(',', '[', ']', '{', '}')) {
                $position++
            }
            $anchor = $Text.Substring($start, $position - $start)
            Assert-YamlNoByteOrderMark -Text $anchor -Mark (
                New-YamlMark -Index ($Context.LineStarts[$Line] + $Column + $start) -Line $Line `
                    -Column ($Column + $start)
            )
            if ([string]::IsNullOrEmpty($anchor) -or $anchor.IndexOfAny(@('[', ']', '{', '}', ',')) -ge 0) {
                $mark = New-YamlMark -Index ($Context.LineStarts[$Line] + $Column + $start - 1) -Line $Line `
                    -Column ($Column + $start - 1)
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlInvalidAnchor' -Message (
                        'A YAML anchor name is missing or malformed.'
                    ))
            }
            continue
        }
        break
    }

    [pscustomobject]@{
        Tag           = $tag
        HasUnknownTag = $unknown
        Anchor        = $anchor
        Rest          = $Text.Substring($position).TrimStart(' ', "`t")
        Consumed      = $position + (
            $Text.Substring($position).Length -
            $Text.Substring($position).TrimStart(' ', "`t").Length
        )
    }
}
