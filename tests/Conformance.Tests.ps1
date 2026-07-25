#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '6.0.0'; MaximumVersion = '6.*' }

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSReviewUnusedParameter', '',
    Justification = 'Required for Pester tests'
)]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSUseDeclaredVarsMoreThanAssignments', '',
    Justification = 'Required for Pester tests'
)]
[CmdletBinding()]
param()

BeforeAll {
    $archivePath = Join-Path $PSScriptRoot 'fixtures\yaml-test-suite\yaml-test-suite-data-2022-01-17.zip'
    $sourcesPath = Join-Path $PSScriptRoot 'fixtures\yaml-test-suite\SOURCES.txt'
    $repositoryRoot = Split-Path -Parent $PSScriptRoot
    $suitePath = Join-Path $TestDrive 'yaml-test-suite'
    . (Join-Path $PSScriptRoot 'TestBootstrap.ps1')
    $conformanceYamlModule = $yamlModule
    Expand-Archive -LiteralPath $archivePath -DestinationPath $suitePath
    $suiteRoots = @(
        Get-ChildItem -LiteralPath $suitePath -Directory
    )
    if ($suiteRoots.Count -ne 1) {
        throw "Expected one release archive root, but found $($suiteRoots.Count)."
    }
    $suiteDataPath = $suiteRoots[0].FullName
    $runnerPath = Join-Path $PSScriptRoot 'tools\Invoke-YamlTestSuite.ps1'
    $suiteResults = @(
        & $runnerPath `
            -Path $suiteDataPath `
            -CompareJson `
            -CompareEvents `
            -CompareOutYaml `
            -CompareEmitYaml `
            -CompareSelfRoundTrip `
            -CompareFormatter
    )
    $emptySuitePath = Join-Path $TestDrive 'empty-suite'
    $null = New-Item -Path $emptySuitePath -ItemType Directory
    . $runnerPath -Path $emptySuitePath -CompareJson
}

Describe 'Released yaml-test-suite corpus accounting' {
    It 'uses the built module for conformance in GitHub Actions' {
        if ($env:GITHUB_ACTIONS -eq 'true') {
            $conformanceYamlModule | Should -Not -BeNullOrEmpty
            $command = Get-Command -Name ConvertFrom-Yaml
            $command.Module | Should -Be $conformanceYamlModule
            (Get-Command -Name Format-Yaml).Module | Should -Be $conformanceYamlModule
            $conformanceYamlModule.ModuleBase |
                Should -Not -Be (Join-Path $repositoryRoot 'src')
            $conformanceYamlModule.PowerShellVersion | Should -Be '7.6'
            @($conformanceYamlModule.CompatiblePSEditions) | Should -Be @('Core')
        }
    }

    It 'uses the pinned unmodified release archive' {
        (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash |
            Should -Be '47C173AFFEB480517B30FB77DC8C76FD48609B9B65DD1C1D3D0D0BAEE48D6AA9'
        $suiteResults.Count | Should -Be 402
    }

    It 'pins the latest official source and data release attribution' {
        $sources = Get-Content -LiteralPath $sourcesPath -Raw

        $sources | Should -Match 'Latest source release:\s+v2022-01-17'
        $sources | Should -Match '45db50aecf9b1520f8258938c88f396e96f30831'
        $sources | Should -Match '6e6c296ae9c9d2d5c4134b4b64d01b29ac19ff6f'
    }

    It 'accounts for syntax recognition and representation-key load policy' {
        @($suiteResults | Where-Object SyntaxResult -EQ 'Pass').Count | Should -Be 400
        @($suiteResults | Where-Object SyntaxResult -EQ 'PolicyDifference').Count |
            Should -Be 2
        @($suiteResults | Where-Object SyntaxResult -EQ 'Fail').Count | Should -Be 0
        @($suiteResults | Where-Object SyntaxResult -EQ 'NotApplicable').Count |
            Should -Be 0
        $policyResults = @(
            $suiteResults |
                Where-Object SyntaxResult -EQ 'PolicyDifference' |
                Sort-Object Case
        )
        @($policyResults.Case) | Should -Be @('2JQS', 'X38W')
        @($policyResults.SyntaxReason | Select-Object -Unique) |
            Should -Be @('RepresentationMappingKeyUniqueness')
        @($policyResults | Where-Object EventResult -NE 'Pass').Count | Should -Be 0
    }

    It 'accounts for parser representation/event comparisons' {
        @($suiteResults | Where-Object EventResult -EQ 'Pass').Count | Should -Be 308
        @($suiteResults | Where-Object EventResult -EQ 'PolicyDifference').Count |
            Should -Be 0
        @($suiteResults | Where-Object EventResult -EQ 'Fail').Count | Should -Be 0
        @($suiteResults | Where-Object EventResult -EQ 'NotApplicable').Count |
            Should -Be 94
    }

    It 'accounts for JSON construction comparisons' {
        @($suiteResults | Where-Object JsonResult -EQ 'Pass').Count | Should -Be 277
        @($suiteResults | Where-Object JsonResult -EQ 'PolicyDifference').Count |
            Should -Be 2
        @($suiteResults | Where-Object JsonResult -EQ 'Fail').Count | Should -Be 0
        @($suiteResults | Where-Object JsonResult -EQ 'NotApplicable').Count |
            Should -Be 123
        $policyResults = @(
            $suiteResults |
                Where-Object JsonResult -EQ 'PolicyDifference' |
                Sort-Object Case
        )
        @($policyResults.Case) | Should -Be @('565N', 'J7PZ')
        @($policyResults.JsonReason) | Should -Be @(
            'BinaryByteArrayProjection',
            'LegacyOrderedMapProjection'
        )
    }

    It 'does not mask altered JSON values as projection policy' {
        $mutatedSuitePath = Join-Path $TestDrive 'mutated-policy-cases'
        $null = New-Item -Path $mutatedSuitePath -ItemType Directory -Force
        foreach ($case in @('565N', 'J7PZ')) {
            Copy-Item -LiteralPath (Join-Path $suiteDataPath $case) `
                -Destination $mutatedSuitePath -Recurse
        }

        $binaryJsonPath = Join-Path $mutatedSuitePath '565N\in.json'
        $binaryJson = Get-Content -LiteralPath $binaryJsonPath -Raw |
            ConvertFrom-Json -AsHashtable
        $binaryJson['description'] = 'Altered expected value'
        $binaryJson | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $binaryJsonPath -Encoding utf8NoBOM

        $orderedMapJsonPath = Join-Path $mutatedSuitePath 'J7PZ\in.json'
        $orderedMapJson = Get-Content -LiteralPath $orderedMapJsonPath -Raw |
            ConvertFrom-Json -AsHashtable
        $orderedMapJson[0]['Mark McGwire'] = 66
        $orderedMapJson | ConvertTo-Json -Depth 10 |
            Set-Content -LiteralPath $orderedMapJsonPath -Encoding utf8NoBOM

        $mutatedResults = @(
            & (Join-Path $PSScriptRoot 'tools\Invoke-YamlTestSuite.ps1') `
                -Path $mutatedSuitePath `
                -CompareJson
        )
        @($mutatedResults | Sort-Object Case | Select-Object -ExpandProperty Case) |
            Should -Be @('565N', 'J7PZ')
        @($mutatedResults | Where-Object JsonResult -EQ 'PolicyDifference').Count |
            Should -Be 0
        @($mutatedResults | Where-Object JsonResult -EQ 'Fail').Count | Should -Be 2
        @($mutatedResults.JsonReason | Select-Object -Unique) |
            Should -Be @('ConstructedValueMismatch')
    }

    It 'canonicalizes binary, complex-key, ordered, and unsupported values distinctly' {
        (ConvertTo-YamlSuiteCanonicalValue -Value ([byte[]] @(1, 2))) |
            Should -Not -Be (ConvertTo-YamlSuiteCanonicalValue -Value ([byte[]] @(3, 4)))

        $firstComplex = [System.Collections.Specialized.OrderedDictionary]::new()
        $secondComplex = [System.Collections.Specialized.OrderedDictionary]::new()
        $firstComplex.Add([object[]] @('a'), 1)
        $secondComplex.Add([object[]] @('b'), 1)
        (ConvertTo-YamlSuiteCanonicalValue -Value $firstComplex) |
            Should -Not -Be (ConvertTo-YamlSuiteCanonicalValue -Value $secondComplex)

        $firstOrder = [System.Collections.Specialized.OrderedDictionary]::new()
        $secondOrder = [System.Collections.Specialized.OrderedDictionary]::new()
        $firstOrder.Add('a', 1)
        $firstOrder.Add('b', 2)
        $secondOrder.Add('b', 2)
        $secondOrder.Add('a', 1)
        $ordinarySameOrder = [System.Collections.Specialized.OrderedDictionary]::new()
        $ordinarySameOrder.Add('a', 1)
        $ordinarySameOrder.Add('b', 2)
        (ConvertTo-YamlSuiteCanonicalValue -Value $firstOrder) |
            Should -Be (ConvertTo-YamlSuiteCanonicalValue -Value $secondOrder)

        $orderedMappings = [System.Collections.Generic.HashSet[object]]::new(
            [System.Collections.Generic.ReferenceEqualityComparer]::Instance
        )
        [void] $orderedMappings.Add($firstOrder)
        [void] $orderedMappings.Add($secondOrder)
        (ConvertTo-YamlSuiteCanonicalValue -Value $firstOrder `
            -OrderedMappings $orderedMappings) |
            Should -Not -Be (
                ConvertTo-YamlSuiteCanonicalValue -Value $secondOrder `
                    -OrderedMappings $orderedMappings
            )
        (ConvertTo-YamlSuiteCanonicalValue -Value $firstOrder `
            -OrderedMappings $orderedMappings) |
            Should -Not -Be (
                ConvertTo-YamlSuiteCanonicalValue -Value $ordinarySameOrder `
                    -OrderedMappings $orderedMappings
            )

        $firstNestedKey = [System.Collections.Specialized.OrderedDictionary]::new()
        $secondNestedKey = [System.Collections.Specialized.OrderedDictionary]::new()
        $firstNestedKey.Add($firstOrder, 'value')
        $secondNestedKey.Add($secondOrder, 'value')
        (ConvertTo-YamlSuiteCanonicalValue -Value $firstNestedKey) |
            Should -Be (ConvertTo-YamlSuiteCanonicalValue -Value $secondNestedKey)
        (ConvertTo-YamlSuiteCanonicalValue -Value $firstNestedKey `
            -OrderedMappings $orderedMappings) |
            Should -Not -Be (
                ConvertTo-YamlSuiteCanonicalValue -Value $secondNestedKey `
                    -OrderedMappings $orderedMappings
            )

        (ConvertTo-YamlSuiteCanonicalValue -Value ([uri] 'https://example.com/one')) |
            Should -Not -Be (
                ConvertTo-YamlSuiteCanonicalValue -Value ([uri] 'https://example.com/two')
            )
    }

    It 'includes binary and complex mapping-key identity in reference signatures' {
        $sharedBytes = [byte[]] @(1, 2)
        $sharedBinaryGraph = [object[]] @($sharedBytes, $sharedBytes)
        $distinctBinaryGraph = [object[]] @([byte[]] @(1, 2), [byte[]] @(1, 2))
        (ConvertTo-YamlSuiteReferenceSignature -Value $sharedBinaryGraph) |
            Should -Not -Be (ConvertTo-YamlSuiteReferenceSignature -Value $distinctBinaryGraph)

        $sharedKey = [object[]] @('key')
        $sharedKeyGraph = [System.Collections.Specialized.OrderedDictionary]::new()
        $sharedKeyGraph.Add($sharedKey, $sharedKey)
        $distinctKeyGraph = [System.Collections.Specialized.OrderedDictionary]::new()
        $distinctKeyGraph.Add([object[]] @('key'), [object[]] @('key'))
        (ConvertTo-YamlSuiteReferenceSignature -Value $sharedKeyGraph) |
            Should -Not -Be (ConvertTo-YamlSuiteReferenceSignature -Value $distinctKeyGraph)
    }

    It 'detects altered ordered-map and alias semantics in out.yaml' {
        $mutatedSuitePath = Join-Path $TestDrive 'mutated-out-cases'
        $null = New-Item -Path $mutatedSuitePath -ItemType Directory -Force
        foreach ($case in @('J7PZ', 'UGM3')) {
            Copy-Item -LiteralPath (Join-Path $suiteDataPath $case) `
                -Destination $mutatedSuitePath -Recurse
        }

        @'
--- !!omap
- Sammy Sosa: 63
- Mark McGwire: 65
- Ken Griffy: 58
'@ | Set-Content -LiteralPath (Join-Path $mutatedSuitePath 'J7PZ\out.yaml') `
            -Encoding utf8NoBOM

        $invoicePath = Join-Path $mutatedSuitePath 'UGM3\out.yaml'
        $invoice = Get-Content -LiteralPath $invoicePath -Raw
        $duplicateAddress = @'
ship-to:
  given: Chris
  family: Dumars
  address:
    lines: |
      458 Walkman Dr.
      Suite #292
    city: Royal Oak
    state: MI
    postal: 48046
'@
        $invoice.Replace('ship-to: *id001', $duplicateAddress.TrimEnd()) |
            Set-Content -LiteralPath $invoicePath -Encoding utf8NoBOM

        $mutatedResults = @(
            & $runnerPath -Path $mutatedSuitePath -CompareOutYaml
        )
        @($mutatedResults | Where-Object OutYamlResult -EQ 'Fail').Count | Should -Be 2
        @($mutatedResults | Sort-Object Case | Select-Object -ExpandProperty OutYamlReason) |
            Should -Be @('OutYamlConstructionMismatch', 'OutYamlReferenceMismatch')
    }

    It 'ignores source order for ordinary mapping out.yaml comparisons' {
        $ordinarySuitePath = Join-Path $TestDrive 'ordinary-mapping-order'
        $ordinaryCasePath = Join-Path $ordinarySuitePath 'ordinary-map'
        $null = New-Item -Path $ordinaryCasePath -ItemType Directory -Force
        "a: 1`nb: 2" | Set-Content -LiteralPath (Join-Path $ordinaryCasePath 'in.yaml') `
            -Encoding utf8NoBOM
        "b: 2`na: 1" | Set-Content -LiteralPath (Join-Path $ordinaryCasePath 'out.yaml') `
            -Encoding utf8NoBOM

        $ordinaryResult = & $runnerPath -Path $ordinarySuitePath -CompareOutYaml

        $ordinaryResult.OutYamlResult | Should -Be 'Pass'
    }

    It 'detects explicit ordered-map tag loss across representation surfaces' {
        $tagLossSuitePath = Join-Path $TestDrive 'ordered-map-tag-loss'
        $tagLossCasePath = Join-Path $tagLossSuitePath 'omap-tag-loss'
        $null = New-Item -Path $tagLossCasePath -ItemType Directory -Force
        "!!omap`n- a: 1`n- b: 2" |
            Set-Content -LiteralPath (Join-Path $tagLossCasePath 'in.yaml') `
                -Encoding utf8NoBOM
        foreach ($fixture in @('out.yaml', 'emit.yaml')) {
            "a: 1`nb: 2" |
                Set-Content -LiteralPath (Join-Path $tagLossCasePath $fixture) `
                    -Encoding utf8NoBOM
        }

        $tagLossResult = & $runnerPath -Path $tagLossSuitePath `
            -CompareOutYaml -CompareEmitYaml -CompareSelfRoundTrip

        $tagLossResult.OutYamlResult | Should -Be 'Fail'
        $tagLossResult.OutYamlReason | Should -Be 'OutYamlConstructionMismatch'
        $tagLossResult.EmitYamlResult | Should -Be 'Fail'
        $tagLossResult.EmitYamlReason | Should -Be 'EmitYamlRepresentationMismatch'
        $tagLossResult.SelfRoundTripResult | Should -Be 'PolicyDifference'
        $tagLossResult.SelfRoundTripReason | Should -Be 'LegacyOrderedMapProjection'
    }

    It 'accounts for out.yaml representation comparisons' {
        @($suiteResults | Where-Object OutYamlResult -EQ 'Pass').Count | Should -Be 241
        @($suiteResults | Where-Object OutYamlResult -EQ 'PolicyDifference').Count |
            Should -Be 1
        @($suiteResults | Where-Object OutYamlResult -EQ 'Fail').Count | Should -Be 0
        @($suiteResults | Where-Object OutYamlResult -EQ 'NotApplicable').Count |
            Should -Be 160
        $outPolicy = $suiteResults | Where-Object OutYamlResult -EQ 'PolicyDifference'
        $outPolicy.Case | Should -Be 'X38W'
        $outPolicy.OutYamlReason | Should -Be 'RepresentationMappingKeyUniqueness'
    }

    It 'validates the 55 official emit.yaml fixtures separately' {
        @($suiteResults | Where-Object HasEmitYaml).Count | Should -Be 55
        @($suiteResults | Where-Object EmitYamlResult -EQ 'Pass').Count | Should -Be 55
        @($suiteResults | Where-Object EmitYamlResult -EQ 'PolicyDifference').Count |
            Should -Be 0
        @($suiteResults | Where-Object EmitYamlResult -EQ 'Fail').Count | Should -Be 0
        @($suiteResults | Where-Object EmitYamlResult -EQ 'NotApplicable').Count |
            Should -Be 347
    }

    It 'reads official emit.yaml content rather than counting its presence' {
        $mutatedSuitePath = Join-Path $TestDrive 'mutated-emit-fixture'
        $null = New-Item -Path $mutatedSuitePath -ItemType Directory -Force
        Copy-Item -LiteralPath (Join-Path $suiteDataPath '2LFX') `
            -Destination $mutatedSuitePath -Recurse
        '--- altered' | Set-Content `
            -LiteralPath (Join-Path $mutatedSuitePath '2LFX\emit.yaml') `
            -Encoding utf8NoBOM

        $mutatedResult = & $runnerPath -Path $mutatedSuitePath -CompareEmitYaml

        $mutatedResult.EmitYamlResult | Should -Be 'Fail'
        $mutatedResult.EmitYamlReason | Should -Be 'EmitYamlRepresentationMismatch'
    }

    It 'uses JSON as the oracle for invalid-source emit fixtures' {
        $mutatedSuitePath = Join-Path $TestDrive 'mutated-invalid-emit-fixtures'
        $null = New-Item -Path $mutatedSuitePath -ItemType Directory -Force
        Copy-Item -LiteralPath (Join-Path $suiteDataPath 'DK95') `
            -Destination $mutatedSuitePath -Recurse
        foreach ($case in @('01', '06')) {
            '--- altered' | Set-Content `
                -LiteralPath (Join-Path $mutatedSuitePath "DK95\$case\emit.yaml") `
                -Encoding utf8NoBOM
        }

        $mutatedResults = @(
            & $runnerPath -Path $mutatedSuitePath -CompareEmitYaml
        )
        $invalidFixtureResults = @(
            $mutatedResults |
                Where-Object Case -In @('DK95/01', 'DK95/06') |
                Sort-Object Case
        )

        @($invalidFixtureResults.EmitYamlResult) | Should -Be @('Fail', 'Fail')
        @($invalidFixtureResults.EmitYamlReason | Select-Object -Unique) |
            Should -Be @('EmitYamlRepresentationMismatch')
    }

    It 'does not run module emission while validating official fixtures' {
        $independentSuitePath = Join-Path $TestDrive 'independent-emit-fixture'
        $independentCasePath = Join-Path $independentSuitePath 'deep-fixture'
        $null = New-Item -Path $independentCasePath -ItemType Directory -Force
        $deepYaml = ('[' * 101) + 'value' + (']' * 101)
        $deepYaml | Set-Content -LiteralPath (Join-Path $independentCasePath 'in.yaml') `
            -Encoding utf8NoBOM -NoNewline
        $deepYaml | Set-Content -LiteralPath (Join-Path $independentCasePath 'emit.yaml') `
            -Encoding utf8NoBOM -NoNewline

        $independentResult = & $runnerPath -Path $independentSuitePath -CompareEmitYaml

        $independentResult.EmitYamlResult | Should -Be 'Pass'
        $independentResult.SelfRoundTripResult | Should -Be 'NotApplicable'
    }

    It 'accounts honestly for general module self-round-trips' {
        @($suiteResults | Where-Object SelfRoundTripResult -EQ 'Pass').Count |
            Should -Be 305
        @($suiteResults | Where-Object SelfRoundTripResult -EQ 'PolicyDifference').Count |
            Should -Be 3
        @($suiteResults | Where-Object SelfRoundTripResult -EQ 'Fail').Count |
            Should -Be 0
        @($suiteResults | Where-Object SelfRoundTripResult -EQ 'NotApplicable').Count |
            Should -Be 94
        $policyResults = @(
            $suiteResults |
                Where-Object SelfRoundTripResult -EQ 'PolicyDifference' |
                Sort-Object Case
        )
        @($policyResults.Case) | Should -Be @('2JQS', 'J7PZ', 'X38W')
        @($policyResults.SelfRoundTripReason) | Should -Be @(
            'RepresentationMappingKeyUniqueness',
            'LegacyOrderedMapProjection',
            'RepresentationMappingKeyUniqueness'
        )
    }

    It 'formats every loadable case with representation and idempotence preserved' {
        @($suiteResults | Where-Object FormatterResult -EQ 'Pass').Count |
            Should -Be 400
        @($suiteResults | Where-Object FormatterResult -EQ 'PolicyDifference').Count |
            Should -Be 0
        @($suiteResults | Where-Object FormatterResult -EQ 'Fail').Count |
            Should -Be 0
        @($suiteResults | Where-Object FormatterResult -EQ 'NotApplicable').Count |
            Should -Be 2

        $excluded = @(
            $suiteResults |
                Where-Object FormatterResult -EQ 'NotApplicable' |
                Sort-Object Case
        )
        @($excluded.Case) | Should -Be @('2JQS', 'X38W')
        @($excluded.FormatterReason | Select-Object -Unique) |
            Should -Be @('RepresentationMappingKeyUniqueness')

        $formatted = @(
            $suiteResults |
                Where-Object { -not $_.ExpectsError -and $_.FormatterResult -eq 'Pass' }
        )
        $formatted.Count | Should -Be 306
        @($formatted | Where-Object FormatterReason).Count | Should -Be 0
        @($formatted | Where-Object { $_.FormatterText -cne $_.FormatterSecond }).Count |
            Should -Be 0
        @($formatted | Where-Object { $_.FormatterExpected -cne $_.FormatterActual }).Count |
            Should -Be 0
    }

    It 'keeps every invalid corpus input rejected by the formatter' {
        $invalid = @($suiteResults | Where-Object ExpectsError)

        $invalid.Count | Should -Be 94
        @($invalid | Where-Object FormatterResult -NE 'Pass').Count | Should -Be 0
        @($invalid.FormatterReason | Select-Object -Unique) |
            Should -Be @('InvalidInputRejected')
    }

    It 'keeps the previously failing multi-document JSON cases green' {
        $jsonRegressions = @(
            $suiteResults |
                Where-Object Case -In @(
                    '35KP', '6XDY', '6ZKB', '7Z25', '9DXL',
                    '9KAX', 'JHB9', 'KSS4', 'L383', 'M7A3',
                    'PUW8', 'RZT7', 'U9NS', 'UT92', 'W4TN'
                ) |
                Where-Object JsonResult -NE 'Pass'
        )
        $jsonRegressions.Count | Should -Be 0
    }
}
