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
    $suitePath = Join-Path $TestDrive 'yaml-test-suite'
    Expand-Archive -LiteralPath $archivePath -DestinationPath $suitePath
    $suiteResults = @(
        & (Join-Path $PSScriptRoot 'tools\Invoke-YamlTestSuite.ps1') `
            -Path $suitePath `
            -CompareJson `
            -CompareEvents `
            -CompareOutYaml `
            -CompareEmitRoundTrip
    )
}

Describe 'Released yaml-test-suite corpus accounting' {
    It 'uses the pinned unmodified release archive' {
        (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash |
            Should -Be 'DCC1F037B13F6C3032D5190C447B6A6EF5560738A4C104F29B4243B0AB8F8029'
        $suiteResults.Count | Should -Be 402
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

    It 'accounts for out.yaml representation comparisons' {
        @($suiteResults | Where-Object OutYamlResult -EQ 'Pass').Count | Should -Be 241
        @($suiteResults | Where-Object OutYamlResult -EQ 'PolicyDifference').Count |
            Should -Be 0
        @($suiteResults | Where-Object OutYamlResult -EQ 'Fail').Count | Should -Be 0
        @($suiteResults | Where-Object OutYamlResult -EQ 'NotApplicable').Count |
            Should -Be 161
    }

    It 'accounts for emitter and round-trip comparisons' {
        @($suiteResults | Where-Object EmitResult -EQ 'Pass').Count | Should -Be 306
        @($suiteResults | Where-Object EmitResult -EQ 'PolicyDifference').Count |
            Should -Be 0
        @($suiteResults | Where-Object EmitResult -EQ 'Fail').Count | Should -Be 0
        @($suiteResults | Where-Object EmitResult -EQ 'NotApplicable').Count |
            Should -Be 96
    }

    It 'keeps the previously failing multi-document JSON cases green' {
        @(
            $suiteResults |
                Where-Object Case -In @(
                    '35KP', '6XDY', '6ZKB', '7Z25', '9DXL',
                    '9KAX', 'JHB9', 'KSS4', 'L383', 'M7A3',
                    'PUW8', 'RZT7', 'U9NS', 'UT92', 'W4TN'
                ) |
                Where-Object JsonResult -NE 'Pass'
        ).Count | Should -Be 0
    }
}
