function ConvertTo-YamlParserCompatibleText {
    <#
        .SYNOPSIS
        Folds valid multiline flow syntax rejected by the YamlDotNet parser.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string] $Yaml
    )

    $lines = [System.Text.RegularExpressions.Regex]::Split($Yaml, '\r?\n')
    if ($lines.Count -le 1) {
        return $Yaml
    }

    $builder = [System.Text.StringBuilder]::new()
    $flowIndents = [System.Collections.Generic.Stack[int]]::new()
    $trimLeading = $false
    $inSingleQuote = $false
    $inDoubleQuote = $false

    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $originalLine = $lines[$lineIndex]
        $leadingLength = $originalLine.Length - $originalLine.TrimStart(' ').Length
        $line = if ($trimLeading) {
            $originalLine.TrimStart(' ')
        } else {
            $originalLine
        }
        $trimLeading = $false
        $hasComment = $false
        $previousSignificant = [char] 0

        for ($characterIndex = 0; $characterIndex -lt $line.Length; $characterIndex++) {
            $character = $line[$characterIndex]

            if ($inDoubleQuote) {
                if ($character -eq '\') {
                    $characterIndex++
                } elseif ($character -eq '"') {
                    $inDoubleQuote = $false
                }
                continue
            }

            if ($inSingleQuote) {
                if ($character -eq "'") {
                    if ($characterIndex + 1 -lt $line.Length -and $line[$characterIndex + 1] -eq "'") {
                        $characterIndex++
                    } else {
                        $inSingleQuote = $false
                    }
                }
                continue
            }

            $commentStart = $characterIndex -eq 0 -or [char]::IsWhiteSpace($line[$characterIndex - 1])
            if ($character -eq '#' -and $commentStart) {
                $hasComment = $true
                break
            }
            if ($character -eq '"') {
                $inDoubleQuote = $true
                continue
            }
            if ($character -eq "'") {
                $inSingleQuote = $true
                continue
            }

            if ($character -eq '{' -or $character -eq '[') {
                $isCollectionStart = $previousSignificant -eq [char] 0
                $isCollectionStart = $isCollectionStart -or $previousSignificant -in @(':', '-', '?', ',', '[', '{')
                if ($isCollectionStart) {
                    $flowIndents.Push($leadingLength)
                }
            } elseif (($character -eq '}' -or $character -eq ']') -and $flowIndents.Count -gt 0) {
                [void] $flowIndents.Pop()
            }

            if (-not [char]::IsWhiteSpace($character)) {
                $previousSignificant = $character
            }
        }

        [void] $builder.Append($line)
        if ($lineIndex -eq $lines.Count - 1) {
            continue
        }

        $nextLine = $lines[$lineIndex + 1]
        $nextIndent = $nextLine.Length - $nextLine.TrimStart(' ').Length
        $canFoldStructuralLine = $flowIndents.Count -gt 0
        $canFoldStructuralLine = $canFoldStructuralLine -and -not $hasComment
        $canFoldStructuralLine = $canFoldStructuralLine -and -not $inSingleQuote
        $canFoldStructuralLine = $canFoldStructuralLine -and -not $inDoubleQuote
        $canFoldStructuralLine = $canFoldStructuralLine -and $nextLine.Trim().Length -gt 0
        $canFoldStructuralLine = $canFoldStructuralLine -and $nextIndent -gt $flowIndents.Peek()

        if ($canFoldStructuralLine) {
            [void] $builder.Append(' ')
            $trimLeading = $true
        } else {
            [void] $builder.Append("`n")
        }
    }

    return $builder.ToString()
}
