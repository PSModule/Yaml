function New-YamlException {
    <#
        .SYNOPSIS
        Creates a location-aware YAML validation exception.

        .DESCRIPTION
        Formats a parser or constructor failure message with one-based start and
        end line and column information. It stores YAML-specific metadata on the
        exception so public cmdlets can later create classified ErrorRecords.

        .EXAMPLE
        New-YamlException -Start (New-YamlMark -Index 0 -Line 0 -Column 0) -End (New-YamlMark -Index 4 -Line 0 -Column 4) `
            -Message 'Invalid YAML scalar.' -ErrorId 'YamlInvalidScalar'

        Returns a FormatException with location text and YAML error metadata.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory exception without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([System.FormatException])]
    param (
        # The first source mark for the YAML construct that failed validation.
        [Parameter(Mandatory)]
        [pscustomobject] $Start,

        # The final source mark for the YAML construct that failed validation.
        [Parameter(Mandatory)]
        [pscustomobject] $End,

        # The human-readable YAML validation message to include before location.
        [Parameter(Mandatory)]
        [string] $Message,

        # The stable YAML error identifier preserved for ErrorRecord creation.
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
