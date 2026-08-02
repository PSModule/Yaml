function New-YamlSerializationException {
    <#
        .SYNOPSIS
        Creates a typed YAML serialization exception.

        .DESCRIPTION
        Creates the InvalidOperationException or NotSupportedException used by the serializer and
        stores the YAML-specific error id in the exception data. This keeps private helpers
        reporting consistent errors back to ConvertTo-Yaml without duplicating exception wiring.

        .EXAMPLE
        New-YamlSerializationException -Message 'The object graph contains a cycle.' -ErrorId 'YamlCycleDetected'

        Returns an InvalidOperationException decorated with the YAML error identifier.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertTo-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory exception without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([System.Exception])]
    param (
        # The message explains the serialization failure that will be surfaced to callers.
        [Parameter(Mandatory)]
        [string] $Message,

        # The stable YAML error id lets callers identify the precise serializer failure.
        [Parameter(Mandatory)]
        [string] $ErrorId,

        # The exception kind selects the .NET category that best matches the failure.
        [Parameter()]
        [ValidateSet('InvalidOperation', 'NotSupported')]
        [string] $Kind = 'InvalidOperation'
    )

    $exception = if ($Kind -eq 'NotSupported') {
        [System.NotSupportedException]::new($Message)
    } else {
        [System.InvalidOperationException]::new($Message)
    }
    $exception.Data['YamlErrorId'] = $ErrorId
    Write-Output -InputObject $exception -NoEnumerate
}
