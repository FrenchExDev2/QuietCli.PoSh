#requires -Version 7.6
# Contracts between tooling-ci.yml and the script test platform: every script test host, every mutation target, one completion gate.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-QuietTestLibrary -Name CiCompanions
    Import-QuietTestLibrary -Name ScriptMutation
    $root=Get-QuietTestWorkspaceRoot
    # Reading the catalogue loads the pinned YAML parser shipped with Core.
    $null=Read-QuietCiCompanions -WorkspaceRoot $root
    $workflow=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build().Deserialize([IO.File]::ReadAllText([IO.Path]::Combine($root,'.github','workflows','tooling-ci.yml'),[Text.Encoding]::UTF8))
    $jobs=$workflow['jobs']
    $runs={param($Job)(@($Job['steps']|ForEach-Object {[string]$_['run']})) -join "`n"}
    $uses={param($Job,$Prefix)@($Job['steps']|Where-Object {([string]$_['uses']).StartsWith($Prefix,[StringComparison]::Ordinal)})}
    $indexOf={param($Job,$Step)[Array]::IndexOf(@($Job['steps']),$Step)}
    $targets=@(Read-QuietScriptMutationTargets -Path ([IO.Path]::Combine($root,'test','scripts','mutation.targets.psd1')) -ScriptsRoot ([IO.Path]::Combine($root,'scripts')) -TestsRoot ([IO.Path]::Combine($root,'test','scripts')))
}

Describe 'tooling-ci.yml script tests' {
    It 'runs every script test with coverage on Windows and Linux' {
        (@($jobs['script-tests']['strategy']['matrix']['os'])|Sort-Object -CaseSensitive) -join ','|Should -BeExactly 'ubuntu-latest,windows-latest'
        $commands=& $runs $jobs['script-tests']
        $commands|Should -Match ([regex]::Escape('./scripts/Initialize-TestTools.ps1'))
        $commands|Should -Match ([regex]::Escape('./scripts/Invoke-ScriptsTests.ps1 -Headless -Coverage'))
        $commands|Should -Not -Match '-Kind|-Path|-FullNameFilter|-Tag' -Because 'a filtered run is partial and never qualifies'
    }

    It 'restores the pinned test tool archives before initializing them' -ForEach @(@{Job='script-tests'},@{Job='script-mutation'}) {
        $restore=@(& $uses $jobs[$Job] './.github/actions/cache-test-tools')
        $restore.Count|Should -Be 1
        $initialize=@($jobs[$Job]['steps']|Where-Object {([string]$_['run']).Contains('./scripts/Initialize-TestTools.ps1')})[0]
        (& $indexOf $jobs[$Job] $restore[0])|Should -BeLessThan (& $indexOf $jobs[$Job] $initialize)
    }
}

Describe 'tooling-ci.yml script mutation' {
    It 'shards exactly the configured targets, one job each' {
        (@($jobs['script-mutation']['strategy']['matrix']['target'])|Sort-Object -CaseSensitive) -join ','|Should -BeExactly ((@($targets.Name)|Sort-Object -CaseSensitive) -join ',')
        [string]$jobs['script-mutation']['strategy']['fail-fast']|Should -BeExactly 'false'
        $commands=& $runs $jobs['script-mutation']
        $commands|Should -Match ([regex]::Escape('./scripts/Invoke-ScriptsMutation.ps1 -Headless -Offline -PruneCache -Target $env:MUTATION_TARGET'))
        [string]@($jobs['script-mutation']['steps']|Where-Object {$_['id'] -ceq 'script_mutation'})[0]['env']['MUTATION_TARGET']|Should -BeExactly '${{ matrix.target }}'
        $commands|Should -Not -Match '-NoCache' -Because 'the content-addressed cache is what makes a shard incremental'
    }

    It 'restores the newest cache of its own target and saves it even after a failed campaign' {
        $job=$jobs['script-mutation']
        $campaign=@($job['steps']|Where-Object {$_['id'] -ceq 'script_mutation'})[0]
        $restore=@(& $uses $job 'actions/cache/restore@')
        $save=@(& $uses $job 'actions/cache/save@')
        $restore.Count|Should -Be 1
        $save.Count|Should -Be 1
        @(& $uses $job 'actions/cache@').Count|Should -Be 0 -Because 'the implicit post-job save of actions/cache skips failed jobs'
        $key='${{ runner.os }}-quietcli-script-mutation-${{ matrix.target }}-${{ github.run_id }}-${{ github.run_attempt }}'
        foreach($step in $restore[0],$save[0]){
            [string]$step['with']['path']|Should -BeExactly '.cache/script-mutation'
            [string]$step['with']['key']|Should -BeExactly $key
        }
        ([string]$restore[0]['with']['restore-keys']).Trim()|Should -BeExactly '${{ runner.os }}-quietcli-script-mutation-${{ matrix.target }}-' -Because 'a shard never reads another target''s outcomes'
        [string]$save[0]['if']|Should -Match '^always\(\)'
        (& $indexOf $job $restore[0])|Should -BeLessThan (& $indexOf $job $campaign)
        (& $indexOf $job $save[0])|Should -BeGreaterThan (& $indexOf $job $campaign)
        [string]$restore[0]['uses']|Should -BeExactly ([string]$save[0]['uses']).Replace('/save@','/restore@') -Because 'both halves pin the same release'
    }

    It 'requires every shard of this revision and attempt before accepting the campaign' {
        $complete=$jobs['script-mutation-complete']
        @($complete['needs'])|Should -Be @('script-mutation')
        [string]$complete['if']|Should -BeExactly '${{ always() && !cancelled() }}'
        $download=@($complete['steps']|Where-Object {([string]$_['uses']).StartsWith('actions/download-artifact@',[StringComparison]::Ordinal)})[0]
        [string]$download['with']['pattern']|Should -BeExactly 'quietcli-script-mutation-${{ github.sha }}-*-attempt${{ github.run_attempt }}'
        $upload=@($jobs['script-mutation']['steps']|Where-Object {([string]$_['uses']).StartsWith('actions/upload-artifact@',[StringComparison]::Ordinal)})[0]
        [string]$upload['with']['name']|Should -BeExactly 'quietcli-script-mutation-${{ github.sha }}-${{ matrix.target }}-attempt${{ github.run_attempt }}'
        $commands=& $runs $complete
        $commands|Should -Match "if\(\`$env:SHARD_RESULT -cne 'success'\)\{throw 'ScriptMutationShardJobsRequired'\}"
        $commands|Should -Match ([regex]::Escape('./scripts/Assert-ScriptMutationShards.ps1 -ReportRoot ./artifacts/script-mutation-shards'))
    }
}

Describe 'tooling-ci.yml results' {
    It 'reports the script jobs through the existing functional, mutation and completion results' {
        $needs=@($jobs['results']['needs'])
        foreach($name in 'script-tests','script-mutation','script-mutation-complete'){$needs|Should -Contain $name}
        [string]$jobs['results']['if']|Should -BeExactly '${{ always() }}'
        (& $runs $jobs['results'])|Should -Match ([regex]::Escape('./scripts/Write-ToolingResults.ps1 -NeedsJson $env:TOOLING_NEEDS'))
    }
}
