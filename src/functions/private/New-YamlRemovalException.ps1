function New-YamlRemovalException {
    <#
        .SYNOPSIS
        Creates a classified exception for a YAML removal failure.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Constructs an in-memory exception without changing system state.'
    )]
    [CmdletBinding()]
    [OutputType([System.FormatException])]
    param (
        [Parameter(Mandatory)]
        [string] $ErrorId,

        [Parameter(Mandatory)]
        [string] $Message,

        [Parameter()]
        [AllowNull()]
        [pscustomobject] $Node
    )

    if ($null -eq $Node) {
        $mark = New-YamlMark -Index 0 -Line 0 -Column 0
        return New-YamlException -Start $mark -End $mark -ErrorId $ErrorId -Message $Message
    }

    return New-YamlException -Start $Node.Start -End $Node.End `
        -ErrorId $ErrorId -Message $Message
}
