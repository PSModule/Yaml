function Get-YamlMergePath {
    <#
        .SYNOPSIS
        Creates a stable diagnostic path for one YAML mapping entry.

        .DESCRIPTION
        Builds a stable human-readable path for a child mapping key during
        recursive merge conflict reporting. Scalar string keys use property or
        quoted-index syntax, while complex keys fall back to deterministic entry
        indexes.

        .EXAMPLE
        Get-YamlMergePath -Parent '$.spec' -Key $entry.Key -Index 2

        Returns a diagnostic child path such as $.spec.name or $.spec{key:2}.

        .LINK
        https://psmodule.io/Yaml/Functions/Merge-Yaml/
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        # Carries the already-resolved parent path for nested diagnostics.
        [Parameter(Mandatory)]
        [string] $Parent,

        # Determines the child path segment from the overlay mapping key.
        [Parameter(Mandatory)]
        [pscustomobject] $Key,

        # Provides a deterministic fallback when the key is not a simple string.
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
