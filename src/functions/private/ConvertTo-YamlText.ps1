function ConvertTo-YamlText {
    <#
        .SYNOPSIS
        Emits an internal node graph as LF-normalized YAML text.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [ValidateRange(2, 9)]
        [int] $Indent,

        [switch] $ExplicitDocumentStart
    )

    $builder = [System.Text.StringBuilder]::new()
    if ($ExplicitDocumentStart) {
        [void] $builder.Append("---`n")
    }
    Write-YamlNodeText -Builder $builder -Node $Node -Level 0 -Indent $Indent `
        -EmittedReferences ([System.Collections.Generic.HashSet[long]]::new())
    return $builder.ToString()
}
