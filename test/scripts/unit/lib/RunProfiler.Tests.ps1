#requires -Version 7.6

BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $source=Get-QuietTestScriptsRoot
    $scripts=[IO.Path]::Combine($TestDrive,'scripts')
    $library=[IO.Path]::Combine($scripts,'lib')
    $null=New-Item -Path $library -ItemType Directory -Force
    foreach($name in 'RunProfiler.psm1','RunEncoding.psm1'){
        Copy-Item -LiteralPath ([IO.Path]::Combine($source,'lib',$name)) -Destination $library
    }
    $null=New-QuietTestFile ([IO.Path]::Combine($scripts,'Initialize-Profilers.ps1')) @'
[CmdletBinding(SupportsShouldProcess)]
param($OutputDirectory,$Module)
if($PSBoundParameters['Confirm']){throw 'UnexpectedProfilerConfirmation'}
@{ProfilerModulePath=[IO.Path]::Combine($OutputDirectory,$Module+'.psd1')}
'@
    $fixtureModule=Import-Module ([IO.Path]::Combine($library,'RunProfiler.psm1')) -PassThru -DisableNameChecking -ErrorAction Stop
}

AfterAll {
    if($fixtureModule){Remove-Module -ModuleInfo $fixtureModule -Force}
}

Describe 'Invoke-QuietProfiledTestCommand' {
    It 'keeps tests in the tracing process, returns their output, and restores the worker environment' {
        Mock Invoke-RunProfiled -ModuleName RunProfiler {
            & $ScriptBlock
            $null=New-Item -Path $OutputDirectory -ItemType Directory -Force
            $path=[IO.Path]::Combine($OutputDirectory,$Label+'.profile.json')
            [IO.File]::WriteAllText($path,'{}',[Text.UTF8Encoding]::new($false))
            $path
        }
        $before=$env:QUIETCLI_TEST_CASE_WORKER
        try{
            $env:QUIETCLI_TEST_CASE_WORKER='previous-worker'
            $result=Invoke-QuietProfiledTestCommand -TestCommand {"worker=$env:QUIETCLI_TEST_CASE_WORKER"; 'summary'} -WorkspaceRoot $TestDrive -RunDirectory $TestDrive -Suite Box
            $env:QUIETCLI_TEST_CASE_WORKER|Should -BeExactly 'previous-worker'
        }finally{$env:QUIETCLI_TEST_CASE_WORKER=$before}
        $result.Output|Should -BeExactly @('worker=1','summary')
        $result.Profiling.State|Should -BeExactly 'Success'
        $result.Profiling.Companion|Should -BeExactly 'Box'
        $result.Profiling.Report|Should -BeExactly ([IO.Path]::Combine($TestDrive,'profiling','Box.profile.json'))
        Should -Invoke Invoke-RunProfiled -ModuleName RunProfiler -Exactly -Times 1 -ParameterFilter {
            $Label -ceq 'Box' -and $ProfilerModulePath -ceq [IO.Path]::Combine($TestDrive,'.cache','profilers','profiler.psd1')
        }
    }

    It 'requires a written trace before reporting success and restores the worker environment on failure' {
        Mock Invoke-RunProfiled -ModuleName RunProfiler { [IO.Path]::Combine($OutputDirectory,'missing.json') }
        $before=$env:QUIETCLI_TEST_CASE_WORKER
        {Invoke-QuietProfiledTestCommand -TestCommand {'summary'} -WorkspaceRoot $TestDrive -RunDirectory $TestDrive -Suite Box} | Should -Throw '*CompanionProfilingReportMissing*'
        $env:QUIETCLI_TEST_CASE_WORKER|Should -Be $before
    }
}
