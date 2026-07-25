function New-YamlSerializationException {
    <#
        .SYNOPSIS
        Creates a typed YAML serialization exception.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory exception without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([System.Exception])]
    param (
        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory)]
        [string] $ErrorId,

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
