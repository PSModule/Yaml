function Get-YamlTextEncoding {
    <#
        .SYNOPSIS
        Creates a strict text encoding for YAML file input or output.

        .DESCRIPTION
        Returns an encoding that throws when bytes or characters cannot be
        represented. The encoding preamble matches the public encoding name.

        .PARAMETER Name
        The public YAML file encoding name.

        .EXAMPLE
        Get-YamlTextEncoding -Name utf8

        Returns strict UTF-8 without a byte order mark.

        .INPUTS
        None.

        .OUTPUTS
        System.Text.Encoding
    #>
    [OutputType(
        [System.Text.UTF8Encoding],
        [System.Text.UnicodeEncoding],
        [System.Text.UTF32Encoding]
    )]
    [CmdletBinding()]
    param (
        # Selects the strict decoder and its output preamble policy.
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
