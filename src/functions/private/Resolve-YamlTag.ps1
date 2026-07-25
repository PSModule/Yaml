function Resolve-YamlTag {
    <#
        .SYNOPSIS
        Expands, budgets, and classifies one YAML tag token.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [string] $Token,

        [Parameter(Mandatory)]
        [pscustomobject] $Context,

        [Parameter(Mandatory)]
        [pscustomobject] $Mark
    )

    if (-not $Token.StartsWith('!', [System.StringComparison]::Ordinal)) {
        throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                "The tag token '$Token' is malformed."
            ))
    }

    $isNonSpecific = $Token.Equals('!', [System.StringComparison]::Ordinal)
    if ($Token.StartsWith('!<', [System.StringComparison]::Ordinal)) {
        if (-not $Token.EndsWith('>', [System.StringComparison]::Ordinal) -or $Token.Length -lt 4) {
            throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                    "The tag token '$Token' is malformed."
                ))
        }
        $suffix = $Token.Substring(2, $Token.Length - 3)
        if (-not (Test-YamlTagUriText -Text $suffix)) {
            throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                    "The tag token '$Token' contains invalid URI text."
                ))
        }
        $prefix = ''
    } else {
        $handle = '!'
        $suffix = $Token.Substring(1)
        if ($Token.StartsWith('!!', [System.StringComparison]::Ordinal)) {
            $handle = '!!'
            $suffix = $Token.Substring(2)
        } else {
            $secondBang = $Token.IndexOf('!', 1)
            if ($secondBang -ge 1) {
                $handle = $Token.Substring(0, $secondBang + 1)
                $suffix = $Token.Substring($secondBang + 1)
            }
        }
        if ($Token.Equals('!', [System.StringComparison]::Ordinal)) {
            $prefix = ''
            $suffix = '!'
        } elseif ([string]::IsNullOrEmpty($suffix) -or
            -not (Test-YamlTagUriText -Text $suffix -Shorthand)) {
            throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlInvalidTag' -Message (
                    "The tag token '$Token' contains an invalid shorthand suffix."
                ))
        }
        if (-not $Context.TagHandles.ContainsKey($handle)) {
            throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlUndefinedTagHandle' -Message (
                    "The tag handle '$handle' was not declared."
                ))
        }
        if (-not $Token.Equals('!', [System.StringComparison]::Ordinal)) {
            $prefix = $Context.TagHandles[$handle]
        }
    }

    $expanded = if ($isNonSpecific) {
        ''
    } else {
        ConvertFrom-YamlTagUriEscape -Text ($prefix + $suffix) -Mark $Mark -Token $Token `
            -MaxLength $Context.MaxTagLength
    }
    $expandedLength = $expanded.Length
    if ($expandedLength -gt $Context.MaxTagLength) {
        throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlTagLimitExceeded' -Message (
                "A YAML tag exceeds the configured limit of $($Context.MaxTagLength) characters."
            ))
    }
    $Context.TotalTagLength += $expandedLength
    if ($Context.TotalTagLength -gt $Context.MaxTotalTagLength) {
        throw (New-YamlException -Start $Mark -End $Mark -ErrorId 'YamlTagLimitExceeded' -Message (
                "The YAML stream exceeds the configured cumulative tag limit of $($Context.MaxTotalTagLength) characters."
            ))
    }

    $known = $expanded -cin @(
        'tag:yaml.org,2002:binary',
        'tag:yaml.org,2002:bool',
        'tag:yaml.org,2002:float',
        'tag:yaml.org,2002:int',
        'tag:yaml.org,2002:map',
        'tag:yaml.org,2002:null',
        'tag:yaml.org,2002:omap',
        'tag:yaml.org,2002:pairs',
        'tag:yaml.org,2002:seq',
        'tag:yaml.org,2002:set',
        'tag:yaml.org,2002:str',
        'tag:yaml.org,2002:timestamp'
    )

    [pscustomobject]@{
        Tag       = $expanded
        IsUnknown = $isNonSpecific -or -not $known
    }
}
