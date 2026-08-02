function ConvertTo-Yaml {
    <#
        .SYNOPSIS
        Converts PowerShell values to YAML 1.2-compatible text.

        .DESCRIPTION
        Normalizes supported PowerShell values into mappings, sequences, and
        scalars before emitting YAML with the module's repository-owned YAML
        emitter. PowerShell metadata is not serialized. Repeated acyclic
        references use YAML anchors and aliases; cyclic and unsupported values
        terminate with a specific error.

        Multiple pipeline records are collected into one top-level sequence.

        .EXAMPLE
        [ordered]@{ name = 'Ada'; active = $true } | ConvertTo-Yaml

        Converts one mapping to YAML.

        .EXAMPLE
        'one', 'two' | ConvertTo-Yaml

        Converts two pipeline records to one YAML sequence.

        .INPUTS
        System.Object

        The value to serialize. Multiple pipeline records are collected into one sequence.

        .OUTPUTS
        System.String

        The YAML 1.2-compatible text emitted for the input values.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # The value to serialize. Multiple pipeline records are collected into
        # a single top-level YAML sequence.
        [Parameter(Mandatory, Position = 0, ValueFromPipeline)]
        [AllowNull()]
        [object] $InputObject,

        # Cap object-graph nesting depth so deep or hostile graphs can't exhaust
        # the stack.
        [Parameter()]
        [ValidateRange(1, 128)]
        [int] $Depth = 100,

        # Cap the total number of traversed nodes to bound memory and time.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxNodes = 100000,

        # Cap the character count of any single emitted scalar.
        [Parameter()]
        [ValidateRange(1, 2147483647)]
        [int] $MaxScalarLength = 1048576,

        # Number of spaces per block-indentation level in the emitted YAML.
        [Parameter()]
        [ValidateRange(2, 9)]
        [int] $Indent = 2,

        # Emit an explicit `---` document-start marker ahead of the content.
        [Parameter()]
        [switch] $ExplicitDocumentStart,

        # Emit enum names as strings instead of their underlying numeric values.
        [Parameter()]
        [switch] $EnumsAsStrings
    )

    begin {
        $values = [System.Collections.Generic.List[object]]::new()
        $inspectionState = [pscustomobject]@{
            MaxScalarLength = $MaxScalarLength
            MaxNodes        = $MaxNodes
            NodeCount       = 0
        }
    }
    process {
        try {
            $null = Get-YamlSerializationShape -Value $InputObject -State $inspectionState `
                -EnumsAsStrings:$EnumsAsStrings -InspectOnly
            if ($values.Count -gt 0 -and ($values.Count + 2) -gt $MaxNodes) {
                throw (New-YamlSerializationException -ErrorId 'YamlNodeLimitExceeded' -Message (
                        "The object graph exceeds the configured limit of $MaxNodes nodes."
                    ))
            }
        } catch [System.NotSupportedException] {
            $record = New-YamlErrorRecord -Exception $_.Exception `
                -DefaultErrorId 'YamlUnsupportedType' -Category InvalidType -TargetObject $InputObject
            $PSCmdlet.ThrowTerminatingError($record)
        } catch [System.InvalidOperationException] {
            $record = New-YamlErrorRecord -Exception $_.Exception `
                -DefaultErrorId 'YamlSerializationFailed' -Category InvalidOperation `
                -TargetObject $InputObject
            $PSCmdlet.ThrowTerminatingError($record)
        }
        $values.Add($InputObject)
    }
    end {
        if ($values.Count -eq 0) {
            if (-not $PSBoundParameters.ContainsKey('InputObject')) {
                return
            }
            $value = [object[]]::new(0)
        } elseif ($values.Count -eq 1) {
            $value = [object] $values[0]
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
            ReservedNodeCount = 0
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
