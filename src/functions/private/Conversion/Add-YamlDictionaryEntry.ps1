function Add-YamlDictionaryEntry {
    <#
        .SYNOPSIS
        Adds a projected mapping entry with a YAML-classified collision error.

        .DESCRIPTION
        Inserts a constructed YAML mapping key and value into an internal
        dictionary used by PowerShell projection. It reclassifies .NET duplicate
        key collisions as YAML projection errors tied to the original key node.

        .EXAMPLE
        Add-YamlDictionaryEntry -Dictionary ([ordered]@{}) -Key 'name' -Value 'Ada' -KeyNode $keyNode

        Adds the name entry or throws a YAML projection collision if the key is not distinct.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Mutates an internal projection dictionary.'
    )]
    [CmdletBinding()]
    param (
        # The target projection dictionary that receives the constructed entry.
        [Parameter(Mandatory)]
        [System.Collections.IDictionary] $Dictionary,

        # The projected key whose distinctness depends on the dictionary comparer.
        [Parameter(Mandatory)]
        [object] $Key,

        # The projected value to store; null is valid for YAML null and set values.
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value,

        # The source key node used to locate any projection key collision.
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
