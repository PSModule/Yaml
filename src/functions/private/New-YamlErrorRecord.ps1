function New-YamlErrorRecord {
    <#
        .SYNOPSIS
        Creates a public error record from an internal YAML exception.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory error record without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([System.Management.Automation.ErrorRecord])]
    param (
        [Parameter(Mandatory)]
        [System.Exception] $Exception,

        [Parameter(Mandatory)]
        [string] $DefaultErrorId,

        [Parameter(Mandatory)]
        [System.Management.Automation.ErrorCategory] $Category,

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
