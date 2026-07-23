function Write-YamlNodeText {
    <#
        .SYNOPSIS
        Iteratively writes an emission graph in deterministic YAML block form.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Appends deterministic text to an in-memory builder.'
    )]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Text.StringBuilder] $Builder,

        [Parameter(Mandatory)]
        [pscustomobject] $Node,

        [Parameter(Mandatory)]
        [ValidateRange(0, 128)]
        [int] $Level,

        [Parameter(Mandatory)]
        [ValidateRange(2, 9)]
        [int] $Indent,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.HashSet[long]] $EmittedReferences,

        [AllowEmptyString()]
        [string] $LeadingText = ''
    )

    $stack = [System.Collections.Generic.Stack[object]]::new()
    $stack.Push([pscustomobject]@{
            Type        = 'Node'
            Node        = $Node
            Entry       = $null
            Level       = $Level
            LeadingText = $LeadingText
        })

    while ($stack.Count -gt 0) {
        $task = $stack.Pop()
        if ($task.Type -eq 'Entry') {
            $keyText = ConvertTo-YamlFlowText -Node $task.Entry.Key `
                -EmittedReferences $EmittedReferences
            $explicitKey = (
                Get-YamlEmissionImplicitKeyLength -RenderedText $keyText
            ) -gt 1024
            if ($explicitKey) {
                $spaces = ' ' * ($task.Level * $Indent)
                [void] $Builder.Append($spaces).Append('? ').Append($keyText).Append("`n")
            }
            $stack.Push([pscustomobject]@{
                    Type        = 'Node'
                    Node        = $task.Entry.Value
                    Entry       = $null
                    Level       = $task.Level
                    LeadingText = if ($explicitKey) { ': ' } else { "$keyText`: " }
                })
            continue
        }

        $current = $task.Node
        $spaces = ' ' * ($task.Level * $Indent)
        if ($current.ReferenceId -ne 0 -and
            $EmittedReferences.Contains($current.ReferenceId)) {
            [void] $Builder.Append($spaces).Append($task.LeadingText).
            Append('*').Append($current.Anchor).Append("`n")
            continue
        }

        $isEmptyCollection = (
            ($current.Kind -eq 'Sequence' -and $current.Items.Count -eq 0) -or
            ($current.Kind -eq 'Mapping' -and $current.Entries.Count -eq 0)
        )
        if ($current.Kind -eq 'Scalar' -or $isEmptyCollection) {
            $flow = ConvertTo-YamlFlowText -Node $current `
                -EmittedReferences $EmittedReferences
            [void] $Builder.Append($spaces).Append($task.LeadingText).
            Append($flow).Append("`n")
            continue
        }

        if ($current.ReferenceId -ne 0) {
            [void] $EmittedReferences.Add($current.ReferenceId)
        }
        $prefix = Get-YamlEmissionPrefix -Node $current
        $childLevel = $task.Level
        if (-not [string]::IsNullOrEmpty($task.LeadingText)) {
            [void] $Builder.Append($spaces).Append($task.LeadingText)
            if (-not [string]::IsNullOrEmpty($prefix)) {
                [void] $Builder.Append($prefix)
            }
            [void] $Builder.Append("`n")
            $childLevel++
        } elseif (-not [string]::IsNullOrEmpty($prefix)) {
            [void] $Builder.Append($spaces).Append($prefix).Append("`n")
        }

        if ($current.Kind -eq 'Sequence') {
            for ($index = $current.Items.Count - 1; $index -ge 0; $index--) {
                $stack.Push([pscustomobject]@{
                        Type        = 'Node'
                        Node        = $current.Items[$index]
                        Entry       = $null
                        Level       = $childLevel
                        LeadingText = '- '
                    })
            }
            continue
        }

        for ($index = $current.Entries.Count - 1; $index -ge 0; $index--) {
            $stack.Push([pscustomobject]@{
                    Type        = 'Entry'
                    Node        = $null
                    Entry       = $current.Entries[$index]
                    Level       = $childLevel
                    LeadingText = ''
                })
        }
    }
}
