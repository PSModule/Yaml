function ConvertTo-YamlTimestampText {
    <#
        .SYNOPSIS
        Formats a representable CLR timestamp for YAML emission.
    #>
    [CmdletBinding()]
    [OutputType([string])]
    param (
        [Parameter(Mandatory)]
        [object] $Value
    )

    try {
        if ($Value -is [datetimeoffset]) {
            $offsetMinutes = $Value.Offset.TotalMinutes
            if ($offsetMinutes -lt -840 -or $offsetMinutes -gt 840 -or
                $offsetMinutes -ne [System.Math]::Truncate($offsetMinutes) -or
                $Value.UtcTicks -lt [datetime]::MinValue.Ticks -or
                $Value.UtcTicks -gt [datetime]::MaxValue.Ticks) {
                throw [System.ArgumentOutOfRangeException]::new('Value')
            }
            return $Value.ToString(
                'o',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        }

        if ($Value.Kind -eq [System.DateTimeKind]::Local) {
            return [datetimeoffset]::new($Value).ToString(
                'o',
                [System.Globalization.CultureInfo]::InvariantCulture
            )
        }

        $utc = if ($Value.Kind -eq [System.DateTimeKind]::Utc) {
            $Value
        } else {
            [datetime]::SpecifyKind($Value, [System.DateTimeKind]::Utc)
        }
        return $utc.ToString(
            "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'",
            [System.Globalization.CultureInfo]::InvariantCulture
        )
    } catch [System.ArgumentException] {
        throw (New-YamlSerializationException -ErrorId 'YamlTimestampSerializationFailed' `
                -Message 'The timestamp cannot be represented with its local or explicit UTC offset.')
    } catch [System.FormatException] {
        throw (New-YamlSerializationException -ErrorId 'YamlTimestampSerializationFailed' `
                -Message 'The timestamp cannot be represented with its local or explicit UTC offset.')
    }
}
