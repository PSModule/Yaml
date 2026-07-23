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
    [OutputType([System.FormatException])]
    param (
        [Parameter(Mandatory)]
        [pscustomobject] $Start,

        [Parameter(Mandatory)]
        [pscustomobject] $End,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter(Mandatory)]
        [string] $ErrorId
    )

    $formattedMessage = '{0} Start: line {1}, column {2}. End: line {3}, column {4}.' -f @(
        $Message.TrimEnd('.'),
        ($Start.Line + 1),
        ($Start.Column + 1),
        ($End.Line + 1),
        ($End.Column + 1)
    )
    $exception = [System.FormatException]::new($formattedMessage)
    $exception.Data['YamlErrorId'] = $ErrorId
    $exception.Data['IsYamlException'] = $true
    Write-Output -InputObject $exception -NoEnumerate
}
