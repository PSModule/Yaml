function Read-YamlNodeProperty {
    <#
        .SYNOPSIS
        Reads tag and anchor properties from the start of a node segment.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [Parameter(Mandatory)]
        [int] $Line,

        [Parameter(Mandatory)]
        [int] $Column,

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
            if ($position - $start -gt $Context.MaxTagLength) {
                $mark = New-YamlMark -Index ($Context.LineStarts[$Line] + $Column + $start) -Line $Line `
                    -Column ($Column + $start)
                throw (New-YamlException -Start $mark -End $mark -ErrorId 'YamlTagLimitExceeded' -Message (
                        "A YAML tag token exceeds the configured limit of $($Context.MaxTagLength) characters."
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
