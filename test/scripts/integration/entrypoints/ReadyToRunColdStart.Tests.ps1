#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $scriptsRoot = Get-QuietTestScriptsRoot
    $workspace = [IO.Path]::Combine($TestDrive,'workspace')
    $fixtureScripts = [IO.Path]::Combine($workspace,'scripts')
    $fixtureLib = [IO.Path]::Combine($fixtureScripts,'lib')
    [void][IO.Directory]::CreateDirectory($fixtureLib)
    foreach ($script in 'New-ReadyToRunCandidate.ps1','Invoke-ContainerColdStartWorker.ps1') {
        Copy-Item -LiteralPath ([IO.Path]::Combine($scriptsRoot,$script)) -Destination $fixtureScripts
    }
    Copy-Item -LiteralPath ([IO.Path]::Combine($scriptsRoot,'lib','WorkspaceLayout.psm1')) -Destination $fixtureLib
    $candidateScript = [IO.Path]::Combine($fixtureScripts,'New-ReadyToRunCandidate.ps1')
    $workerScript = [IO.Path]::Combine($fixtureScripts,'Invoke-ContainerColdStartWorker.ps1')
    $moduleName = 'FrenchExDev2.QuietCli.Core.PoSh'
    $moduleRelative = "src/Core/src/$moduleName"
    $baselineRoot = [IO.Path]::Combine($workspace,$moduleRelative)
    $baselineManifest = [IO.Path]::Combine($baselineRoot,$moduleName+'.psd1')
    $null = New-QuietTestFile $baselineManifest '@{}'
    $null = New-QuietTestFile ([IO.Path]::Combine($baselineRoot,'engine','QuietCli.Engine.csproj')) '<Project />'
    foreach ($file in 'global.json','Directory.Build.props','Directory.Packages.props') {
        $null = New-QuietTestFile ([IO.Path]::Combine($workspace,$file)) $file
    }
    foreach ($directory in 'lib/inprocess','lib/engine') {
        $null = New-QuietTestFile ([IO.Path]::Combine($baselineRoot,$directory,'build-manifest.json')) '{"ReadyToRunTargets":[]}'
    }
    Copy-Item -LiteralPath ([IO.Path]::Combine($PSScriptRoot,'..','..','support','ReadyToRunColdStart.Common.psm1')) -Destination ([IO.Path]::Combine($fixtureLib,'Common.psm1'))
}

Describe 'New-ReadyToRunCandidate.ps1' {
    It 'publishes both framework slots for the requested RID in the grouped copy' {
        $destination = [IO.Path]::Combine($TestDrive,'candidate')
        $run = Invoke-QuietTestScript -ScriptPath $candidateScript -ArgumentList @(
            '-WorkspaceRoot',$workspace,'-CandidateRoot',$destination,'-RuntimeIdentifier','linux-musl-arm64')
        $run.ExitCode | Should -Be 0 -Because ($run.Output+$run.Error)
        $module = [IO.Path]::Combine($destination,$moduleRelative)
        $run.Output.Trim() | Should -BeExactly ([IO.Path]::Combine($module,$moduleName+'.psd1'))
        $frameworks = @{ 'lib/inprocess'='net10.0'; 'lib/engine'='net11.0' }
        foreach ($directory in $frameworks.Keys) {
            $copied = [IO.Path]::Combine($module,$directory)
            $publish = Get-Content -LiteralPath ([IO.Path]::Combine($copied,'linux-musl-arm64','publish.json')) -Raw -Encoding utf8 | ConvertFrom-Json
            $publish.Arguments[3] | Should -BeExactly $frameworks[$directory]
            $publish.Arguments | Should -Contain '-p:PlatformTarget=ARM64'
            $publish.Arguments | Should -Contain '-p:PublishReadyToRun=true'
            $receipt = Get-Content -LiteralPath ([IO.Path]::Combine($copied,'linux-musl-arm64','build-manifest.json')) -Raw -Encoding utf8 | ConvertFrom-Json
            $receipt.ReadyToRun | Should -BeTrue
            $selected = Get-Content -LiteralPath ([IO.Path]::Combine($copied,'build-manifest.json')) -Raw -Encoding utf8 | ConvertFrom-Json
            ($selected.ReadyToRunTargets -join ',') | Should -BeExactly 'linux-musl-arm64'
            $baseline = Get-Content -LiteralPath ([IO.Path]::Combine($baselineRoot,$directory,'build-manifest.json')) -Raw -Encoding utf8 | ConvertFrom-Json
            $baseline.ReadyToRunTargets.Count | Should -Be 0
        }
    }

    It 'previews without creating the destination' {
        $destination = [IO.Path]::Combine($TestDrive,'preview')
        $run = Invoke-QuietTestScript -ScriptPath $candidateScript -ArgumentList @(
            '-WorkspaceRoot',$workspace,'-CandidateRoot',$destination,'-RuntimeIdentifier','linux-musl-arm64','-WhatIf')
        $run.ExitCode | Should -Be 0 -Because $run.Error
        $destination | Should -Not -Exist
    }
}

Describe 'Invoke-ContainerColdStartWorker.ps1' {
    It 'passes staged module paths and the expected A/A setting when direct A/B is <Direct>' -ForEach @(
        @{ Direct = $false }
        @{ Direct = $true }
    ) {
        $candidateManifest = [IO.Path]::Combine($TestDrive,'prebuilt',$moduleName+'.psd1')
        $null = New-QuietTestFile $candidateManifest '@{}'
        $runDirectory = [IO.Path]::Combine($workspace,"run-$Direct")
        [void][IO.Directory]::CreateDirectory($runDirectory)
        $arguments = @(
            '-WorkspaceRoot',$workspace,'-RunDirectory',$runDirectory,'-Image','fixture','-Platform','alpine',
            '-CandidateModule',$candidateManifest,'-ExpectedRuntimeIdentifier','linux-musl-arm64','-ContainerRuntime','docker'
        )
        if ($Direct) { $arguments += '-SkipAaControl' }
        $run = Invoke-QuietTestScript -ScriptPath $workerScript -ArgumentList $arguments -Environment @{
            FIXTURE_COLDSTART_RUN = [IO.Path]::GetFileName($runDirectory); FIXTURE_COLDSTART_DIRECT = [string]$Direct
        }
        $summary = Get-Content -LiteralPath ([IO.Path]::Combine($runDirectory,'summary.json')) -Raw -Encoding utf8 | ConvertFrom-Json
        $run.ExitCode | Should -Be 0 -Because ($summary.State.Error+$run.Error)
        $summary.State.State | Should -BeExactly 'Success'
        $summary.State.ReportFile | Should -BeExactly 'ab-fixture.json'
    }

    It 'fails a nonzero direct A/B guest exit with report present <HasReport>' -ForEach @(
        @{ HasReport = $false }
        @{ HasReport = $true }
    ) {
        $candidateManifest = New-QuietTestFile ([IO.Path]::Combine($TestDrive,'failure-candidate',$moduleName+'.psd1')) '@{}'
        $runDirectory = [IO.Path]::Combine($workspace,"failed-$HasReport")
        [void][IO.Directory]::CreateDirectory($runDirectory)
        $run = Invoke-QuietTestScript -ScriptPath $workerScript -ArgumentList @(
            '-WorkspaceRoot',$workspace,'-RunDirectory',$runDirectory,'-Image','fixture','-Platform','alpine',
            '-CandidateModule',$candidateManifest,'-ExpectedRuntimeIdentifier','linux-musl-arm64','-ContainerRuntime','docker','-SkipAaControl'
        ) -Environment @{
            FIXTURE_COLDSTART_RUN = [IO.Path]::GetFileName($runDirectory); FIXTURE_COLDSTART_DIRECT = 'True'
            FIXTURE_COLDSTART_EXIT = '1'; FIXTURE_COLDSTART_REPORT = [string]$HasReport
        }
        $summary = Get-Content -LiteralPath ([IO.Path]::Combine($runDirectory,'summary.json')) -Raw -Encoding utf8 | ConvertFrom-Json
        $run.ExitCode | Should -Be 1
        $summary.State.State | Should -BeExactly 'Crash'
        $summary.State.Error | Should -Match 'GuestColdStartFailed: exit=1'
    }
}
