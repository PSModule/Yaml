function Test-YamlDocumentPrefix {
    <#
        .SYNOPSIS
        Tests whether text after a BOM is a legal YAML document prefix.
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param (
        [Parameter(Mandatory)]
        [string] $Text,

        [Parameter(Mandatory)]
        [ValidateRange(0, 2147483647)]
        [int] $Index,

        [switch] $RequireDocumentStart
    )

    while ($Index -lt $Text.Length) {
        $lineEnd = $Text.IndexOf("`n", $Index, [System.StringComparison]::Ordinal)
        if ($lineEnd -lt 0) {
            $lineEnd = $Text.Length
        }
        $line = $Text.Substring($Index, $lineEnd - $Index)
        $trimmed = $line.TrimStart(' ', "`t")
        if ($trimmed.Length -eq 0 -or
            $trimmed.StartsWith('#', [System.StringComparison]::Ordinal)) {
            if ($lineEnd -ge $Text.Length) {
                return $false
            }
            $Index = $lineEnd + 1
            continue
        }
        if ($line.StartsWith('%', [System.StringComparison]::Ordinal) -and
            -not $RequireDocumentStart) {
            if ($lineEnd -ge $Text.Length) {
                return $false
            }
            $Index = $lineEnd + 1
            continue
        }
        if (-not $line.StartsWith('---', [System.StringComparison]::Ordinal)) {
            return $false
        }
        return $line.Length -eq 3 -or
        (Test-YamlWhiteSpace -Character $line[3])
    }
    return $false
}
