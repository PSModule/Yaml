# Helper function for recursive object merging
function Merge-YamlObjects {
    param (
        $Base,
        $Override
    )

    if ($Base -is [hashtable] -and $Override -is [hashtable]) {
        $merged = @{}
        foreach ($key in $Base.Keys) {
            if ($Override.ContainsKey($key)) {
                $merged[$key] = Merge-YamlObjects -Base $Base[$key] -Override $Override[$key]
            } else {
                $merged[$key] = $Base[$key]
            }
        }
        foreach ($key in $Override.Keys) {
            if (-not $Base.ContainsKey($key)) {
                $merged[$key] = $Override[$key]
            }
        }
        return $merged
    } elseif ($Base -is [array] -and $Override -is [array]) {
        return $Override  # Replace arrays
    } else {
        return $Override  # Override scalar values
    }
}
