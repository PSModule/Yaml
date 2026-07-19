function New-YamlException {
    <#
        .SYNOPSIS
        Creates a location-aware YAML validation exception.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory exception without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([YamlDotNet.Core.YamlException])]
    param (
        [Parameter(Mandatory)]
        [YamlDotNet.Core.Mark] $Start,

        [Parameter(Mandatory)]
        [YamlDotNet.Core.Mark] $End,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory)]
        [string] $ErrorId
    )

    $formattedMessage = '{0} Start: {1}. End: {2}.' -f @(
        $Message.TrimEnd('.'),
        $Start,
        $End
    )
    $exception = [YamlDotNet.Core.YamlException]::new($formattedMessage)
    $exception.Data['YamlErrorId'] = $ErrorId
    Write-Output -InputObject $exception -NoEnumerate
}
