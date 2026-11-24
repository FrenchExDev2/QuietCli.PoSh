#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $scripts = Get-QuietTestScriptsRoot
    $workspace = [IO.Path]::Combine($TestDrive,'workspace')
    $moduleName = 'FrenchExDev2.QuietCli.Core.PoSh'
    $testsName = 'FrenchExDev2.QuietCli.Core.Tests.PoSh'
    $manifest = [IO.Path]::Combine($workspace,'src','Core','src',$moduleName,"$moduleName.psd1")
    $testsManifest = [IO.Path]::Combine($workspace,'src','Core','test',$testsName,"$testsName.psd1")
    $null = New-QuietTestFile $manifest "@{ ModuleVersion='1.0.0'; PrivateData=@{ QuietCli=@{ TestsModule='$testsName' } } }"
    $null = New-QuietTestFile $testsManifest "@{ ModuleVersion='1.0.0'; RequiredModules=@('$moduleName'); FunctionsToExport=@('Invoke-QuietCoreTests') }"
    $fixtureScripts = [IO.Path]::Combine($workspace,'scripts')
    $fixtureLib = [IO.Path]::Combine($fixtureScripts,'lib')
    [void][IO.Directory]::CreateDirectory($fixtureLib)
    Copy-Item -LiteralPath ([IO.Path]::Combine($scripts,'Invoke-ContainerWorker.ps1')) -Destination $fixtureScripts
    foreach ($name in 'CiCompanions','WorkspaceJson','WorkspaceLayout','WorkspaceProjects') {
        Copy-Item -LiteralPath ([IO.Path]::Combine($scripts,'lib',"$name.psm1")) -Destination $fixtureLib
    }
    $support = [IO.Path]::Combine($PSScriptRoot,'..','..','support','ContainerWorker.Fixture.psm1')
    Copy-Item -LiteralPath $support -Destination ([IO.Path]::Combine($fixtureLib,'Common.psm1'))
    $null = New-QuietTestFile ([IO.Path]::Combine($fixtureLib,'ContainerInputs.psm1')) '# Supplied by the container fixture.'
    $worker = [IO.Path]::Combine($fixtureScripts,'Invoke-ContainerWorker.ps1')
}

Describe 'Invoke-ContainerWorker guest progress' {
    It 'preserves valid progress after a truncated copy and enforces terminal evidence (<Terminal>)' -ForEach @(
        @{ Terminal='valid'; ExitCode=0; State='Success' }
        @{ Terminal='malformed'; ExitCode=1; State='Crash' }
        @{ Terminal='nonzero'; ExitCode=1; State='Crash' }
    ) {
        $reports = [IO.Path]::Combine($TestDrive,$Terminal)
        $result = Invoke-QuietTestScript -ScriptPath $worker -ArgumentList @(
            '-WorkspaceRoot',$workspace,'-RunDirectory',$reports,'-Image','fixture:prepared','-Platform','alpine',
            '-ExpectedRuntimeIdentifier','linux-musl-arm64','-ContainerRuntime','docker','-GitHubActions','-Suite','Core'
        ) -Environment @{ QUIETCLI_FIXTURE_TERMINAL=$Terminal } -TimeoutSeconds 20
        $result.TimedOut | Should -BeFalse
        $result.ExitCode | Should -Be $ExitCode -Because ($result.Output + $result.Error)
        $report = Get-Content -LiteralPath ([IO.Path]::Combine($reports,'summary.json')) -Raw -Encoding utf8 | ConvertFrom-Json
        $report.State.State | Should -BeExactly $State -Because $report.State.Error
        if ($Terminal -ceq 'valid') {
            $report.State.Passed | Should -Be 42
            $report.State.GuestExitCode | Should -Be 0
        } elseif ($Terminal -ceq 'malformed') {
            $report.State.Error | Should -Match "'State'"
        } else {
            $report.State.Error | Should -BeExactly 'GuestExitedNonzeroAfterSuccessReport'
        }
    }
}
