function Get-YamlTextEncoding {
    <#
        .SYNOPSIS
        Creates a strict text encoding for YAML file input or output.

        .DESCRIPTION
        Maps the module's public encoding names to .NET encodings that throw on
        invalid bytes or characters. This keeps Import-Yaml file reads strict
        while preserving the selected byte-order-mark policy for callers.

        .EXAMPLE
        Get-YamlTextEncoding -Name utf8

        Returns strict UTF-8 without a byte order mark.

        .LINK
        https://psmodule.io/Yaml/Functions/Import-Yaml/
    #>
    [OutputType(
        [System.Text.UTF8Encoding],
        [System.Text.UnicodeEncoding],
        [System.Text.UTF32Encoding]
    )]
    [CmdletBinding()]
    param (
        # The public encoding token selects strict decoder behavior and the BOM
        # preamble policy required by file commands.
        [Parameter(Mandatory)]
        [ValidateSet('utf8', 'utf8BOM', 'utf16LE', 'utf16BE', 'utf32LE', 'utf32BE')]
        [string] $Name
    )

    switch ($Name) {
        'utf8' {
            [System.Text.UTF8Encoding]::new($false, $true)
        }
        'utf8BOM' {
            [System.Text.UTF8Encoding]::new($true, $true)
        }
        'utf16LE' {
            [System.Text.UnicodeEncoding]::new($false, $true, $true)
        }
        'utf16BE' {
            [System.Text.UnicodeEncoding]::new($true, $true, $true)
        }
        'utf32LE' {
            [System.Text.UTF32Encoding]::new($false, $true, $true)
        }
        'utf32BE' {
            [System.Text.UTF32Encoding]::new($true, $true, $true)
        }
    }
}
