function Get-YamlMergePath {
    <#
        .SYNOPSIS
        Creates a stable diagnostic path for one YAML mapping entry.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [string] $Parent,

        [Parameter(Mandatory)]
        [pscustomobject] $Key,

        [Parameter(Mandatory)]
        [int] $Index
    )

    $effective = Get-YamlMergeNode -Node $Key
    if ($effective.Kind -eq 'Scalar' -and
        (Get-YamlMergeNodeTag -Node $effective) -ceq 'tag:yaml.org,2002:str') {
        $value = [string] (Resolve-YamlScalar -Node $effective).Value
        if ($value -cmatch '^[A-Za-z_][A-Za-z0-9_-]*$') {
            return "$Parent.$value"
        }
        return "{0}['{1}']" -f $Parent, $value.Replace("'", "''")
    }
    return "$Parent{key:$Index}"
}
