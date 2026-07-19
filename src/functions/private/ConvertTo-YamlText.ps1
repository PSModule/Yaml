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

    $writer = [System.IO.StringWriter]::new(
        [System.Globalization.CultureInfo]::InvariantCulture
    )
    try {
        $settings = [YamlDotNet.Core.EmitterSettings]::new(
            $Indent,
            [int]::MaxValue,
            $false,
            1024,
            $false,
            $false,
            "`n",
            $false
        )
        $emitter = [YamlDotNet.Core.Emitter]::new($writer, $settings)
        $emitter.Emit([YamlDotNet.Core.Events.StreamStart]::new())
        $emitter.Emit(
            [YamlDotNet.Core.Events.DocumentStart]::new(
                $null,
                $null,
                -not $ExplicitDocumentStart
            )
        )
        Write-YamlNodeEvent -Emitter $emitter -Node $Node -EmittedReferences (
            [System.Collections.Generic.HashSet[long]]::new()
        )
        $emitter.Emit([YamlDotNet.Core.Events.DocumentEnd]::new($true))
        $emitter.Emit([YamlDotNet.Core.Events.StreamEnd]::new())
        return $writer.ToString()
    } finally {
        $writer.Dispose()
    }
}
