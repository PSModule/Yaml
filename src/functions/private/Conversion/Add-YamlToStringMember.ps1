function Add-YamlToStringMember {
    <#
        .SYNOPSIS
        Tags a projected YAML document root so ToString renders YAML text.

        .DESCRIPTION
        Adds the PSModule.Yaml.Document type name and a ToString script method to a
        projected mapping or sequence so callers can render the value back to YAML
        text with ToString. Scalars are left untouched because overriding ToString on
        a string, number, or date would change how ordinary values convert to text.

        Rendering is deferred until ToString runs, so decorating a document costs one
        member addition and never serializes eagerly. The script method reports the
        value's current state, which means edits made after parsing are reflected.

        .EXAMPLE
        Add-YamlToStringMember -Value ([pscustomobject]@{ name = 'Ada' })

        Tags the mapping so ToString returns "name": "Ada" instead of an empty string.

        .LINK
        https://psmodule.io/Yaml/Functions/Conversion/ConvertFrom-Yaml/
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'Decorates an in-memory projection result.'
    )]
    [CmdletBinding()]
    [OutputType([void])]
    param (
        # The projected document value to decorate; scalars and null are ignored.
        [Parameter(Mandatory)]
        [AllowNull()]
        [object] $Value
    )

    if (-not (Test-YamlDocumentSurface -Value $Value)) {
        return
    }

    try {
        $Value.PSObject.TypeNames.Insert(0, 'PSModule.Yaml.Document')
        Add-Member -InputObject $Value -MemberType ScriptMethod -Name 'ToString' -Force `
            -ErrorAction Stop -Value {
            try {
                (ConvertTo-Yaml -InputObject $this).TrimEnd("`n")
            } catch {
                $this.PSObject.BaseObject.GetType().FullName
            }
        }
    } catch {
        Write-Debug "Add-YamlToStringMember skipped a document root: $($_.Exception.Message)"
    }
}
