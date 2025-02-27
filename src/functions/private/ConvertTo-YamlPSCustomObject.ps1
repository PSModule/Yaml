# Helper function to convert a hashtable or array to a PSCustomObject recursively
function ConvertTo-YamlPSCustomObject {
    param (
        $Object
    )
    if ($Object -is [hashtable]) {
        $psobj = [PSCustomObject]@{}
        foreach ($key in $Object.Keys) {
            $psobj | Add-Member -MemberType NoteProperty -Name $key -Value (ConvertTo-YamlPSCustomObject -Object $Object[$key])
        }
        return $psobj
    } elseif ($Object -is [array]) {
        return $Object | ForEach-Object { ConvertTo-YamlPSCustomObject -Object $_ }
    } else {
        return $Object
    }
}
