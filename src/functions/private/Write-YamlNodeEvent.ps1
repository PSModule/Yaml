function Write-YamlNodeEvent {
    <#
        .SYNOPSIS
        Writes one normalized node graph to the low-level YAML emitter.
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [YamlDotNet.Core.Emitter] $Emitter,

        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[long]] $EmittedReferences
    )

    if ($Node.ReferenceId -ne 0 -and $EmittedReferences.Contains($Node.ReferenceId)) {
        $Emitter.Emit(
            [YamlDotNet.Core.Events.AnchorAlias]::new(
                [YamlDotNet.Core.AnchorName]::new($Node.Anchor)
            )
        )
        return
    }

    if ($Node.ReferenceId -ne 0) {
        [void] $EmittedReferences.Add($Node.ReferenceId)
    }

    $anchor = if ([string]::IsNullOrEmpty($Node.Anchor)) {
        [YamlDotNet.Core.AnchorName]::Empty
    } else {
        [YamlDotNet.Core.AnchorName]::new($Node.Anchor)
    }
    $tag = if ([string]::IsNullOrEmpty($Node.Tag)) {
        [YamlDotNet.Core.TagName]::Empty
    } else {
        [YamlDotNet.Core.TagName]::new($Node.Tag)
    }

    if ($Node.Kind -eq 'Scalar') {
        $isPlainImplicit = [string]::IsNullOrEmpty($Node.Tag) -and $Node.Style -eq [YamlDotNet.Core.ScalarStyle]::Plain
        $isQuotedImplicit = [string]::IsNullOrEmpty($Node.Tag) -and -not $isPlainImplicit
        $Emitter.Emit(
            [YamlDotNet.Core.Events.Scalar]::new(
                $anchor,
                $tag,
                $Node.Value,
                $Node.Style,
                $isPlainImplicit,
                $isQuotedImplicit
            )
        )
        return
    }

    $isImplicit = [string]::IsNullOrEmpty($Node.Tag)
    if ($Node.Kind -eq 'Sequence') {
        $Emitter.Emit(
            [YamlDotNet.Core.Events.SequenceStart]::new(
                $anchor,
                $tag,
                $isImplicit,
                [YamlDotNet.Core.Events.SequenceStyle]::Block
            )
        )
        foreach ($item in $Node.Items) {
            Write-YamlNodeEvent -Emitter $Emitter -Node $item -EmittedReferences $EmittedReferences
        }
        $Emitter.Emit([YamlDotNet.Core.Events.SequenceEnd]::new())
        return
    }

    $Emitter.Emit(
        [YamlDotNet.Core.Events.MappingStart]::new(
            $anchor,
            $tag,
            $isImplicit,
            [YamlDotNet.Core.Events.MappingStyle]::Block
        )
    )
    foreach ($entry in $Node.Entries) {
        Write-YamlNodeEvent -Emitter $Emitter -Node $entry.Key -EmittedReferences $EmittedReferences
        Write-YamlNodeEvent -Emitter $Emitter -Node $entry.Value -EmittedReferences $EmittedReferences
    }
    $Emitter.Emit([YamlDotNet.Core.Events.MappingEnd]::new())
}
