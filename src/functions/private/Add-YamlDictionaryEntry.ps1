function Add-YamlDictionaryEntry {
    <#
        .SYNOPSIS
        Adds a projected mapping entry with a YAML-classified collision error.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates an internal projection dictionary.'
    )]
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Dictionary,

        [Parameter(Mandatory)]
        [object] $Key,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

        [Parameter(Mandatory)]
        [pscustomobject] $KeyNode
    )

    try {
        $Dictionary.Add($Key, $Value)
    } catch [System.Management.Automation.MethodInvocationException] {
        if ($_.Exception.InnerException -isnot [System.ArgumentException]) {
            throw
        }
        throw (New-YamlException -Start $KeyNode.Start -End $KeyNode.End `
                -ErrorId 'YamlProjectionKeyCollision' -Message (
                'Distinct YAML mapping keys cannot be projected distinctly into a PowerShell dictionary.'
            ))
    }
}
