# Function to calculate the indentation level of a line (assuming 2 spaces per level)
function Get-YamlIndentLevel {
    param (
        [string]$Line
    )
    $indent = 0
    while ($indent -lt $Line.Length -and $Line[$indent] -eq ' ') {
        $indent++
    }
    return [math]::Floor($indent / 2)
}
