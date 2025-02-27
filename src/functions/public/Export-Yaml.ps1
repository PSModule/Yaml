function Export-Yaml {
    param (
        [Parameter(Mandatory = $true)]
        $Object,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $yaml = ConvertTo-Yaml -Object $Object
    Set-Content -Path $Path -Value $yaml
}
