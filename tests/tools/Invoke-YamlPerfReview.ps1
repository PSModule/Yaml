[CmdletBinding()]
param (
    [Parameter()]
    [ValidateSet('Baseline', 'Regression')]
    [string] $Mode = 'Baseline',

    [Parameter()]
    [ValidateRange(1, 200)]
    [int] $Runs = 12,

    [Parameter()]
    [ValidateRange(0, 50)]
    [int] $Preheat = 2,

    [Parameter()]
    [string] $OutputPath = (Join-Path $PSScriptRoot "..\fixtures\perf\$Mode.json")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion -lt [version] '7.6' -or $PSVersionTable.PSEdition -cne 'Core') {
    throw 'Invoke-YamlPerfReview.ps1 requires PowerShell 7.6+ (Core).'
}

Import-Module -Name Profiler -ErrorAction Stop
. (Join-Path $PSScriptRoot '..\TestBootstrap.ps1')

function Get-Percentile {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [double[]] $Values,

        [Parameter(Mandatory)]
        [ValidateRange(0.0, 1.0)]
        [double] $Percentile
    )

    if ($Values.Count -eq 0) {
        return 0.0
    }

    $sorted = @($Values | Sort-Object)
    $index = [Math]::Ceiling($Percentile * $sorted.Count) - 1
    $index = [Math]::Max(0, [Math]::Min($index, $sorted.Count - 1))
    return [double] $sorted[$index]
}

function Measure-Scenario {
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string] $Name,

        [Parameter(Mandatory)]
        [scriptblock] $Script,

        [Parameter(Mandatory)]
        [int] $RunCount,

        [Parameter(Mandatory)]
        [int] $WarmupCount
    )

    for ($i = 0; $i -lt $WarmupCount; $i++) {
        & $Script > $null
    }

    $elapsedMs = [System.Collections.Generic.List[double]]::new()
    for ($i = 0; $i -lt $RunCount; $i++) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        & $Script > $null
        $stopwatch.Stop()
        $elapsedMs.Add($stopwatch.Elapsed.TotalMilliseconds)
    }

    $trace = Trace-Script -ScriptBlock $Script -Preheat 1 -DisableWarning
    $topFunctions = @(
        $trace.Top50FunctionSelfDuration |
            Select-Object -First 5 Function, Module, Line, HitCount, @{
                Name       = 'SelfDurationMs'
                Expression = { [Math]::Round($_.SelfDuration.TotalMilliseconds, 3) }
            }, @{
                Name       = 'DurationMs'
                Expression = { [Math]::Round($_.Duration.TotalMilliseconds, 3) }
            }
    )

    $values = [double[]] $elapsedMs.ToArray()
    [pscustomobject]@{
        Name         = $Name
        Runs         = $RunCount
        Preheat      = $WarmupCount
        AverageMs    = [Math]::Round(($values | Measure-Object -Average).Average, 3)
        MedianMs     = [Math]::Round((Get-Percentile -Values $values -Percentile 0.50), 3)
        P95Ms        = [Math]::Round((Get-Percentile -Values $values -Percentile 0.95), 3)
        MinMs        = [Math]::Round(($values | Measure-Object -Minimum).Minimum, 3)
        MaxMs        = [Math]::Round(($values | Measure-Object -Maximum).Maximum, 3)
        SamplesMs    = $values
        TraceTopSelf = $topFunctions
    }
}

Write-Information "Preparing performance fixtures for mode: $Mode" -InformationAction Continue

$smallYaml = @'
name: small
enabled: true
ports: [80, 443]
'@

$mediumYamlBuilder = [System.Text.StringBuilder]::new()
[void] $mediumYamlBuilder.AppendLine('items:')
for ($index = 0; $index -lt 1200; $index++) {
    [void] $mediumYamlBuilder.AppendLine("  - id: $index")
    [void] $mediumYamlBuilder.AppendLine("    name: item-$index")
    [void] $mediumYamlBuilder.AppendLine("    enabled: true")
    [void] $mediumYamlBuilder.AppendLine("    value: $($index * 3)")
}
$mediumYaml = $mediumYamlBuilder.ToString().TrimEnd("`r", "`n")

$overlayYamlBuilder = [System.Text.StringBuilder]::new()
[void] $overlayYamlBuilder.AppendLine('items:')
for ($index = 0; $index -lt 1200; $index++) {
    [void] $overlayYamlBuilder.AppendLine("  - id: $index")
    [void] $overlayYamlBuilder.AppendLine("    name: item-$index-override")
    [void] $overlayYamlBuilder.AppendLine("    enabled: false")
}
$overlayYaml = $overlayYamlBuilder.ToString().TrimEnd("`r", "`n")

$mediumObject = ConvertFrom-Yaml -Yaml $mediumYaml -NoEnumerate
$tempPath = Join-Path ([System.IO.Path]::GetTempPath()) 'yaml-perf-review.yaml'

$scenarios = @(
    @{
        Name   = 'ConvertFrom-Yaml/small'
        Script = { ConvertFrom-Yaml -Yaml $smallYaml | Out-Null }
    },
    @{
        Name   = 'ConvertFrom-Yaml/medium'
        Script = { ConvertFrom-Yaml -Yaml $mediumYaml -NoEnumerate | Out-Null }
    },
    @{
        Name   = 'ConvertTo-Yaml/medium'
        Script = { ConvertTo-Yaml -InputObject $mediumObject | Out-Null }
    },
    @{
        Name   = 'Format-Yaml/medium'
        Script = { Format-Yaml -InputObject $mediumYaml -Indent 2 | Out-Null }
    },
    @{
        Name   = 'Merge-Yaml/medium'
        Script = { Merge-Yaml -InputObject @($mediumYaml, $overlayYaml) -SequenceAction Replace | Out-Null }
    },
    @{
        Name   = 'Test-Yaml/medium'
        Script = { Test-Yaml -Yaml $mediumYaml | Out-Null }
    },
    @{
        Name   = 'Export-Import-Yaml/medium'
        Script = {
            Export-Yaml -InputObject $mediumObject -Path $tempPath -Force | Out-Null
            Import-Yaml -LiteralPath $tempPath -NoEnumerate | Out-Null
        }
    }
)

$results = [System.Collections.Generic.List[object]]::new()
foreach ($scenario in $scenarios) {
    Write-Information "Measuring $($scenario.Name)" -InformationAction Continue
    $results.Add((Measure-Scenario -Name $scenario.Name -Script $scenario.Script -RunCount $Runs -WarmupCount $Preheat))
}

if (Test-Path -LiteralPath $tempPath) {
    Remove-Item -LiteralPath $tempPath -Force
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    $null = New-Item -Path $outputDirectory -ItemType Directory -Force
}

$report = [pscustomobject]@{
    Mode           = $Mode
    TimestampUtc   = [DateTime]::UtcNow.ToString('o')
    PowerShell     = $PSVersionTable.PSVersion.ToString()
    Edition        = $PSVersionTable.PSEdition
    Runs           = $Runs
    Preheat        = $Preheat
    RegressionFail = 'Greater than 5 percent slowdown on critical-path scenarios.'
    Scenarios      = $results
}

$report | ConvertTo-Json -Depth 8 | Set-Content -Path $OutputPath -Encoding utf8NoBOM
Write-Information "Performance report written to: $OutputPath" -InformationAction Continue
