function New-YamlErrorRecord {
    <#
        .SYNOPSIS
        Creates a public error record from an internal YAML exception.

        .DESCRIPTION
        Wraps an internal exception in a PowerShell ErrorRecord for the public
        ConvertFrom-Yaml surface. It prefers the YAML error id stored on the
        exception and falls back to the caller's default identifier.

        .EXAMPLE
        New-YamlErrorRecord -Exception $exception -DefaultErrorId 'YamlParseFailed' -Category InvalidData -TargetObject $yaml

        Returns an ErrorRecord using the YAML-specific error id when present.

        .LINK
        https://psmodule.io/Yaml/Functions/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory error record without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param (
        # The exception to expose through the PowerShell error stream.
        [Parameter(Mandatory)]
        [System.Exception] $Exception,

        # The fallback error id used when the exception has no YAML metadata.
        [Parameter(Mandatory)]
        [string] $DefaultErrorId,

        # The public PowerShell category that best describes the YAML failure.
        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorCategory] $Category,

        # The original input object associated with the error, if one exists.
        [Parameter()]
        [AllowNull()]
        [object] $TargetObject
    )

    $errorId = $DefaultErrorId
    if ($Exception.Data.Contains('YamlErrorId')) {
        $errorId = [string] $Exception.Data['YamlErrorId']
    }

    $record = [System.Management.Automation.ErrorRecord]::new(
        $Exception,
        $errorId,
        $Category,
        $TargetObject
    )
    Write-Output -InputObject $record -NoEnumerate
}
