function Read-YamlDirectiveBlock {
    <#
        .SYNOPSIS
        Scans one document's directive block and resolves tag handles.
    #>
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Context
    )

    $tagHandles = [System.Collections.Generic.Dictionary[string, string]]::new(
        [System.StringComparer]::Ordinal
    )
    $tagHandles['!'] = '!'
    $tagHandles['!!'] = 'tag:yaml.org,2002:'
    $declaredTagHandles = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::Ordinal
    )
    $yamlDirectiveSeen = $false
    $directiveSeen = $false

    while ($Context.LineIndex -lt $Context.Lines.Count -and
        $Context.Lines[$Context.LineIndex].StartsWith(
            '%',
            [System.StringComparison]::Ordinal
        )) {
        $directiveSeen = $true
        $directive = $Context.Lines[$Context.LineIndex]
        $mark = New-YamlMark -Index $Context.LineStarts[$Context.LineIndex] `
            -Line $Context.LineIndex -Column 0
        Assert-YamlNoByteOrderMark -Text $directive -Mark $mark
        if ($directive -cmatch '^%YAML(?:[ \t]|$)') {
            if ($yamlDirectiveSeen -or $directive -cnotmatch (
                    '^%YAML[ \t]+([0-9]+)\.([0-9]+)(?:[ \t]+#.*)?$'
                ) -or -not $Matches[1].Equals('1', [System.StringComparison]::Ordinal)) {
                throw (New-YamlException -Start $mark -End $mark `
                        -ErrorId 'YamlInvalidDirective' -Message (
                        "The YAML directive '$directive' is malformed, duplicated, or requests an unsupported version."
                    ))
            }
            $yamlDirectiveSeen = $true
        } elseif ($directive -cmatch '^%TAG(?:[ \t]|$)') {
            if ($directive -cnotmatch (
                    '^%TAG[ \t]+(!|!!|![0-9A-Za-z-]+!)[ \t]+([^ \t]+)(?:[ \t]+#.*)?$'
                )) {
                throw (New-YamlException -Start $mark -End $mark `
                        -ErrorId 'YamlInvalidDirective' -Message (
                        "The TAG directive '$directive' is malformed."
                    ))
            }
            $handle = $Matches[1]
            $prefix = $Matches[2]
            if (-not $declaredTagHandles.Add($handle)) {
                throw (New-YamlException -Start $mark -End $mark `
                        -ErrorId 'YamlDuplicateTagHandle' -Message (
                        "The tag handle '$handle' is declared more than once."
                    ))
            }
            if ($prefix.Length -gt $Context.MaxTagLength) {
                throw (New-YamlException -Start $mark -End $mark `
                        -ErrorId 'YamlTagLimitExceeded' -Message (
                        "A YAML tag prefix exceeds the configured limit of $($Context.MaxTagLength) characters."
                    ))
            }
            if (-not $prefix.Equals('!', [System.StringComparison]::Ordinal) -and
                -not (Test-YamlTagUriText -Text $prefix)) {
                throw (New-YamlException -Start $mark -End $mark `
                        -ErrorId 'YamlInvalidDirective' -Message (
                        "The TAG directive prefix '$prefix' contains invalid URI text."
                    ))
            }
            $tagHandles[$handle] = $prefix
        } elseif (-not (Test-YamlReservedDirective -Directive $directive)) {
            throw (New-YamlException -Start $mark -End $mark `
                    -ErrorId 'YamlInvalidDirective' -Message (
                    "The directive '$directive' is malformed."
                ))
        }
        $Context.LineIndex++
        Skip-YamlBlockTrivia -Context $Context
    }

    [pscustomobject]@{
        TagHandles    = $tagHandles
        DirectiveSeen = $directiveSeen
    }
}
