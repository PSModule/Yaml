function ConvertTo-Yaml {
    <#
        .SYNOPSIS
        Converts PowerShell values to YAML 1.2-compatible text.

        .DESCRIPTION
        Normalizes supported PowerShell values into mappings, sequences, and
        scalars before emitting YAML through YamlDotNet's low-level emitter.
        PowerShell metadata is not serialized. Repeated acyclic collection
        references use YAML anchors and aliases; cyclic and unsupported values
        terminate with a specific error.

        Multiple pipeline records are collected into one top-level sequence.

        .PARAMETER InputObject
        A value to serialize. Multiple pipeline records become one sequence.

        .PARAMETER Depth
        Maximum object-graph nesting depth. The default is 100.

        .PARAMETER MaxNodes
        Maximum number of traversed nodes. The default is 100000.

        .PARAMETER MaxScalarLength
        Maximum character count for one emitted scalar. The default is
        1048576.

        .PARAMETER Indent
        Block indentation from 2 through 9 spaces. The default is 2.

        .PARAMETER ExplicitDocumentStart
        Emits an explicit `---` document start marker.

        .PARAMETER EnumsAsStrings
        Emits enum names as strings instead of underlying numeric values.

        .EXAMPLE
        [ordered]@{ name = 'Ada'; active = $true } | ConvertTo-Yaml

        Converts one mapping to YAML.

        .EXAMPLE
        'one', 'two' | ConvertTo-Yaml

        Converts two pipeline records to one YAML sequence.

        .INPUTS
        System.Object

        .OUTPUTS
        System.String
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [object] $InputObject,

        [ValidateRange(1, 1024)]
        [int] $Depth = 100,

        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes = 100000,

        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength = 1048576,

        [ValidateRange(2, 9)]
        [int] $Indent = 2,

        [switch] $ExplicitDocumentStart,

        [switch] $EnumsAsStrings
    )

    begin {
        $values = [System.Collections.Generic.List[object]]::new()
    }
    process {
        $values.Add($InputObject)
    }
    end {
        if ($values.Count -eq 0) {
            if (-not $PSBoundParameters.ContainsKey('InputObject')) {
                return
            }
            $value = [object[]]::new(0)
        } elseif ($values.Count -eq 1) {
            $value = $values[0]
        } else {
            $value = [object[]] $values.ToArray()
        }
        $state = [pscustomobject]@{
            IdGenerator       = [System.Runtime.Serialization.ObjectIDGenerator]::new()
            NodesById         = [System.Collections.Generic.Dictionary[long, object]]::new()
            ReferenceCounts   = [System.Collections.Generic.Dictionary[long, int]]::new()
            ReferenceOrder    = [System.Collections.Generic.List[long]]::new()
            Fingerprints      = [System.Collections.Generic.Dictionary[long, string]]::new()
            FingerprintHasher = [System.Security.Cryptography.SHA256]::Create()
            Active            = [System.Collections.Generic.HashSet[long]]::new()
            NodeCount         = 0
            MaxDepth          = $Depth
            MaxNodes          = $MaxNodes
            MaxScalarLength   = $MaxScalarLength
        }

        try {
            $node = ConvertTo-YamlNode -Value ([object] $value) -State $state -Depth 1 `
                -EnumsAsStrings:$EnumsAsStrings
            Set-YamlNodeAnchor -State $state
            $yaml = ConvertTo-YamlText -Node $node -Indent $Indent `
                -ExplicitDocumentStart:$ExplicitDocumentStart
            $PSCmdlet.WriteObject($yaml, $false)
        } catch [System.NotSupportedException] {
            $record = New-YamlErrorRecord -Exception $_.Exception -DefaultErrorId 'YamlUnsupportedType' `
                -Category InvalidType -TargetObject $value
            $PSCmdlet.ThrowTerminatingError($record)
        } catch [System.InvalidOperationException] {
            $record = New-YamlErrorRecord -Exception $_.Exception -DefaultErrorId 'YamlSerializationFailed' `
                -Category InvalidOperation -TargetObject $value
            $PSCmdlet.ThrowTerminatingError($record)
        } finally {
            $state.FingerprintHasher.Dispose()
        }
    }
}
