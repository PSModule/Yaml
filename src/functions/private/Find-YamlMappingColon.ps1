function Find-YamlMappingColon {
    <#
        .SYNOPSIS
        Finds a block mapping value indicator outside quoted and flow content.
    #>
    [CmdletBinding()]
    [OutputType([int])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Text,

        [switch] $AllowAnchorFallback
    )

    if ($Text.IndexOf(':') -lt 0) {
        return -1
    }

    $flowDepth = 0
    $singleQuoted = $false
    $doubleQuoted = $false
    $atNodeStart = $true
    $anchorColonCandidate = -1
    for ($index = 0; $index -lt $Text.Length; $index++) {
        $character = $Text[$index]
        if ($doubleQuoted) {
            if ($character -eq '\') {
                $index++
            } elseif ($character -eq '"') {
                $doubleQuoted = $false
            }
            continue
        }
        if ($singleQuoted) {
            if ($character -eq "'") {
                if ($index + 1 -lt $Text.Length -and $Text[$index + 1] -eq "'") {
                    $index++
                } else {
                    $singleQuoted = $false
                }
            }
            continue
        }
        if ($atNodeStart -and (Test-YamlWhiteSpace -Character $character)) {
            continue
        }
        if ($atNodeStart -and $character -eq '&') {
            $index++
            while ($index -lt $Text.Length -and
                -not (Test-YamlWhiteSpace -Character $Text[$index]) -and
                $Text[$index] -notin @(',', '[', ']', '{', '}')) {
                if (Test-YamlMappingValueIndicator -Text $Text -Index $index) {
                    $anchorColonCandidate = $index
                }
                $index++
            }
            $index--
            continue
        }
        if ($atNodeStart -and $character -eq '*') {
            $index++
            while ($index -lt $Text.Length -and
                -not (Test-YamlWhiteSpace -Character $Text[$index]) -and
                $Text[$index] -notin @(',', '[', ']', '{', '}')) {
                $index++
            }
            $index--
            continue
        }
        if ($atNodeStart -and $character -eq '!') {
            if ($index + 1 -lt $Text.Length -and $Text[$index + 1] -eq '<') {
                $index = $Text.IndexOf('>', $index + 2)
                if ($index -lt 0) {
                    return -1
                }
            } else {
                $index++
                while ($index -lt $Text.Length -and
                    -not (Test-YamlWhiteSpace -Character $Text[$index]) -and
                    $Text[$index] -notin @('[', ']', '{', '}', ',')) {
                    $index++
                }
                $index--
            }
            continue
        }
        if ($atNodeStart -and $character -eq '"') {
            $doubleQuoted = $true
            $atNodeStart = $false
            continue
        }
        if ($atNodeStart -and $character -eq "'") {
            $singleQuoted = $true
            $atNodeStart = $false
            continue
        }
        $atNodeStart = $false
        switch ($character) {
            '[' { $flowDepth++; continue }
            '{' { $flowDepth++; continue }
            ']' { if ($flowDepth -gt 0) { $flowDepth-- }; continue }
            '}' { if ($flowDepth -gt 0) { $flowDepth-- }; continue }
            ':' {
                if ($flowDepth -eq 0) {
                    $nextIsSeparator = $index + 1 -ge $Text.Length
                    $nextIsSeparator = $nextIsSeparator -or
                    (Test-YamlWhiteSpace -Character $Text[$index + 1])
                    if ($nextIsSeparator) {
                        return $index
                    }
                }
            }
            '#' {
                if ($flowDepth -eq 0 -and (
                        $index -eq 0 -or (Test-YamlWhiteSpace -Character $Text[$index - 1])
                    )) {
                    return -1
                }
            }
        }
    }
    if ($AllowAnchorFallback) {
        return $anchorColonCandidate
    }
    return -1
}
