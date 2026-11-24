#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $scripts = Get-QuietTestScriptsRoot
    $fixtureScripts = [IO.Path]::Combine($TestDrive,'scripts')
    $fixtureLib = [IO.Path]::Combine($fixtureScripts,'lib')
    [void][IO.Directory]::CreateDirectory($fixtureLib)
    foreach ($module in 'Invoke-ColdStartGate','RunLog','RunEncoding','RunFormat') {
        Copy-Item -LiteralPath ([IO.Path]::Combine($scripts,'lib',($module+'.psm1'))) -Destination $fixtureLib
    }
    $null = New-QuietTestFile ([IO.Path]::Combine($fixtureScripts,'Invoke-RunProfile.ps1')) @'
param([string]$Name,[hashtable]$Arguments,[string]$LogLevel,[string]$LogPath)
$aa = $Arguments.CandidateLabel -ceq 'aa-control'
if (!$aa -and $Arguments.FixtureFailure) { throw 'FixtureColdStartFailure' }
$summary = [ordered]@{
    Import = @{ Verdict = if ($aa -and $Arguments.FixtureAaVerdict) { $Arguments.FixtureAaVerdict } else { 'inconclusive' } }
    'First call' = @{ Verdict = 'inconclusive' }
    'Second call' = @{ Verdict = if ($aa -and $Arguments.FixtureSecondVerdict) { $Arguments.FixtureSecondVerdict } else { 'inconclusive' } }
}
@{ Parameters = $Arguments; Summary = $summary } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $Arguments.OutputPath -Encoding utf8
'@
    Import-Module ([IO.Path]::Combine($fixtureLib,'Invoke-ColdStartGate.psm1')) -DisableNameChecking -ErrorAction Stop
}

Describe 'Cold-start comparison and control' {
    BeforeEach {
        $artifacts = [IO.Path]::Combine($TestDrive,[guid]::NewGuid().ToString('N'))
        $baseline = [IO.Path]::Combine($TestDrive,'baseline.psd1')
        $candidate = [IO.Path]::Combine($TestDrive,'candidate.psd1')
        $options = @{ BaselineModule = $baseline; CandidateModule = $candidate; ArtifactsDirectory = $artifacts; LogLevel = 'Off' }
    }

    It 'runs direct A/B even with a malformed A/A cache and accepts inconclusive measurement verdicts' {
        $machine = [Environment]::MachineName.ToLowerInvariant() -replace '[^a-z0-9-]', '-'
        $cache = New-QuietTestFile ([IO.Path]::Combine($artifacts,"aa-coldstart-100-$machine.json")) 'malformed'
        Invoke-QuietScriptInvokeColdStartGate @options -SkipAaControl
        $report = Get-ChildItem -LiteralPath $artifacts -Filter 'ab-*.json' -File
        $report.Count | Should -Be 1
        $data = Get-Content -LiteralPath $report.FullName -Raw -Encoding utf8 | ConvertFrom-Json
        $data.Parameters.BaselineModule | Should -BeExactly $baseline
        $data.Parameters.CandidateModule | Should -BeExactly $candidate
        $data.Summary.Import.Verdict | Should -BeExactly 'inconclusive'
        (Get-Content -LiteralPath $cache -Raw -Encoding utf8) | Should -BeExactly 'malformed'
    }

    It 'uses the selected baseline as both sides of the default A/A control' {
        Invoke-QuietScriptInvokeColdStartGate @options
        $report = Get-ChildItem -LiteralPath $artifacts -Filter 'aa-*.json' -File
        $report.Count | Should -Be 1
        $data = Get-Content -LiteralPath $report.FullName -Raw -Encoding utf8 | ConvertFrom-Json
        $data.Parameters.BaselineModule | Should -BeExactly $baseline
        $data.Parameters.CandidateModule | Should -BeExactly $baseline
        @(Get-ChildItem -LiteralPath $artifacts -Filter 'ab-*.json' -File).Count | Should -Be 1
    }

    It 'rejects an A/A control with a <Verdict> phase and publishes no A/B report' -ForEach @(
        @{ Verdict = 'slower' }
        @{ Verdict = 'faster' }
        @{ Verdict = 'too-few-pairs' }
    ) {
        { Invoke-QuietScriptInvokeColdStartGate @options -Arguments @{ FixtureAaVerdict = $Verdict } } |
            Should -Throw "ColdStartNoiseFloorUnstable: A/A control is not conclusive on this machine (Import=$Verdict); fix noise before trusting any A/B result from it. See *"
        @(Get-ChildItem -LiteralPath $artifacts -Filter 'ab-*.json' -File).Count | Should -Be 0
    }

    It 'propagates a direct comparison failure and leaves no report' {
        { Invoke-QuietScriptInvokeColdStartGate @options -SkipAaControl -Arguments @{ FixtureFailure = $true } } |
            Should -Throw '*FixtureColdStartFailure*'
        @(Get-ChildItem -LiteralPath $artifacts -Filter '*.json' -File).Count | Should -Be 0
    }

    It 'identifies each rejected A/A phase separately' {
        { Invoke-QuietScriptInvokeColdStartGate @options -Arguments @{ FixtureAaVerdict = 'slower'; FixtureSecondVerdict = 'faster' } } |
            Should -Throw '*Import=slower, Second call=faster*'
    }

    It 'previews a direct comparison without creating the artifact directory' {
        Invoke-QuietScriptInvokeColdStartGate @options -SkipAaControl -WhatIf
        $artifacts | Should -Not -Exist
    }
}
