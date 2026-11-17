#requires -Version 7.6
# Contracts between companions-ci.yml (one call of ci.yml per selected suite) and ci.yml (the per-suite engine):
# a develop run has exactly one image producer per RID, and qualification never races it.
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-QuietTestLibrary -Name CiCompanions
    $root=Get-QuietTestWorkspaceRoot
    # Reading the catalogue loads the pinned YAML parser shipped with Core.
    $null=Read-QuietCiCompanions -WorkspaceRoot $root
    $parser=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build()
    $load={param([string]$Name)$parser.Deserialize([IO.File]::ReadAllText([IO.Path]::Combine($root,'.github','workflows',$Name),[Text.Encoding]::UTF8))}
    $companions=& $load 'companions-ci.yml'
    $engine=& $load 'ci.yml'
    $warm=$companions['jobs']['images']
    $producer=$engine['jobs']['linux-images']
    $runs={param($Job)[string[]]@($Job['steps']|ForEach-Object {[string]$_['run']})}
    $stepIndex={param($Job,[scriptblock]$Match)
        $steps=@($Job['steps'])
        for($index=0;$index -lt $steps.Count;$index++){if(& $Match $steps[$index]){return $index}}
        -1
    }
}

Describe 'companions-ci.yml image warm-up' {
    It 'runs once per RID after planning, only for develop pushes or dispatches that qualify products' {
        $warm|Should -Not -BeNullOrEmpty
        (@($warm['needs'])|Sort-Object -CaseSensitive) -join ','|Should -BeExactly 'plan,source-checks' -Because 'the warm-up must not wait for the layout tests, nor depend on qualification'
        $guard=[string]$warm['if']
        foreach($clause in @("needs.plan.outputs.run_products == 'true'","github.repository == 'FrenchExDev2/QuietCli.PoSh'","github.ref == 'refs/heads/develop'","github.event_name == 'push'","github.event_name == 'workflow_dispatch'")){
            $guard.Contains($clause)|Should -BeTrue -Because $clause
        }
        $guard|Should -Not -Match 'pull_request' -Because 'pull requests never publish images'
        [string]$warm['permissions']['packages']|Should -BeExactly 'write'
    }

    It 'serializes every run of the repository per RID without cancelling a publication' {
        [string]$warm['concurrency']['group']|Should -BeExactly 'quietcli2-ci-images-${{ matrix.rid }}'
        [string]$warm['concurrency']['cancel-in-progress']|Should -BeExactly 'false'
        [string]$warm['concurrency']['group']|Should -Not -Match 'inputs\.suite|matrix\.suite' -Because 'one group per RID, shared by every suite of the run'
    }

    It 'probes, restores, prepares the planned image suites base first, then saves the layers' {
        $probe=& $stepIndex $warm {param($step)([string]$step['run']).Contains('-ProbeOnly')}
        $restore=& $stepIndex $warm {param($step)[string]$step['uses'] -ceq './.github/actions/cache-ci-layers' -and [string]$step['with']['mode'] -ceq 'restore'}
        $prepare=& $stepIndex $warm {param($step)([string]$step['run']).Contains('-ResolveOnly')}
        $save=& $stepIndex $warm {param($step)[string]$step['uses'] -ceq './.github/actions/cache-ci-layers' -and [string]$step['with']['mode'] -ceq 'save'}
        foreach($index in $probe,$restore,$prepare,$save){$index|Should -BeGreaterOrEqual 0}
        ($probe -lt $restore -and $restore -lt $prepare -and $prepare -lt $save)|Should -BeTrue
        $steps=@($warm['steps'])
        foreach($index in $probe,$prepare){
            [string]$steps[$index]['env']['IMAGE_SUITES']|Should -BeExactly '${{ needs.plan.outputs.image_suites }}'
            ([string]$steps[$index]['run']).Contains('New-CiSuiteImage.ps1 -Suite ([string[]](ConvertFrom-Json $env:IMAGE_SUITES))')|Should -BeTrue
            [string]$steps[$index]['env']['QUIETCLI_REGISTRY_TOKEN']|Should -BeExactly '${{ github.token }}'
        }
        foreach($switch in '-RegistryCache','-PublishCache','-ResolveOnly','-ContainerRuntime docker'){([string]$steps[$prepare]['run']).Contains($switch)|Should -BeTrue -Because $switch}
        ([string]$steps[$probe]['run']).Contains('-PublishCache')|Should -BeFalse -Because 'a probe never publishes'
        foreach($index in $restore,$save){
            [string]$steps[$index]['if']|Should -BeExactly "steps.image_probe.outputs.cache_hit != 'true'"
            [string]$steps[$index]['with']['fingerprint']|Should -BeExactly '${{ steps.image_probe.outputs.fingerprint }}'
        }
    }

    It 'reuses the same actions, in the same order, as the per-suite producer of ci.yml' {
        $uses={param($Job)(@($Job['steps']|ForEach-Object {[string]$_['uses']}|Where-Object {$_}|ForEach-Object {($_ -split '@')[0]})) -join '|'}
        & $uses $warm|Should -BeExactly (& $uses $producer)
    }

    It 'exposes the planned image suites from the plan step' {
        [string]$companions['jobs']['plan']['outputs']['image_suites']|Should -BeExactly '${{ steps.plan.outputs.image_suites }}'
    }

    It 'warms the same RID and runner rows that ci.yml qualifies' {
        $warmRows=[string[]]@($warm['strategy']['matrix']['include']|ForEach-Object {[string]$_['rid']+'@'+[string]$_['runner']}|Sort-Object -CaseSensitive)
        $definition=(& $runs $engine['jobs']['linux-matrix']) -join "`n"
        $engineRows=[string[]]@([regex]::Matches($definition,"rid='(?<rid>[^']+)';runner='(?<runner>[^']+)'")|ForEach-Object {$_.Groups['rid'].Value+'@'+$_.Groups['runner'].Value}|Sort-Object -CaseSensitive)
        $engineRows.Count|Should -Be 4
        $warmRows -join ','|Should -BeExactly ($engineRows -join ',')
    }
}

Describe 'companions-ci.yml manual qualification' {
    BeforeAll {
        $planStep=@($companions['jobs']['plan']['steps']|Where-Object {[string]$_['id'] -ceq 'plan'})[0]
        # Runs the plan step's own script against a stub planner that records how it was called.
        $invokePlanStep={param([string]$EventName)
            $directory=[IO.Path]::Combine($TestDrive,'plan-step-'+[guid]::NewGuid().ToString('N'))
            $null=New-QuietTestFile ([IO.Path]::Combine($directory,'scripts','New-CiImpactPlan.ps1')) @'
param([string]$Base,[string]$Revision,[string]$Event,[string[]]$Suite,[string]$OutputPath)
[IO.File]::WriteAllText($OutputPath,(ConvertTo-Json -Compress -InputObject ([ordered]@{Bound=@($PSBoundParameters.Keys|Sort-Object);Base=$Base;Revision=$Revision;Event=$Event;Suite=@($Suite)})))
'@
            $step=[IO.Path]::Combine($directory,'step.ps1')
            $null=New-QuietTestFile $step ("Set-Location -LiteralPath `$PSScriptRoot`n"+[string]$planStep['run'])
            $output=[IO.Path]::Combine($directory,'called.json')
            $run=Invoke-QuietTestScript -ScriptPath $step -Environment @{GITHUB_EVENT_NAME=$EventName;GITHUB_SHA=('b'*40);GITHUB_OUTPUT=$output;BASE_SHA=('a'*40);DISPATCH_SUITES='Core,Git'} -TimeoutSeconds 120
            $run.ExitCode|Should -Be 0 -Because ($run.Output+$run.Error)
            [IO.File]::ReadAllText($output)|ConvertFrom-Json
        }
    }

    It 'accepts a manual dispatch whose suites input defaults to every companion' {
        $companions['on'].Keys|Should -Contain 'workflow_dispatch'
        $declared=$companions['on']['workflow_dispatch']['inputs']['suites']
        [string]$declared['type']|Should -BeExactly 'string'
        [string]$declared['required']|Should -BeExactly 'false'
        [string]$declared['default']|Should -BeExactly 'all'
        @($companions['on']['workflow_dispatch']['inputs'].Keys) -join ','|Should -BeExactly 'suites'
    }

    It 'forwards the dispatch input, not a base, to the planner' {
        [string]$planStep['env']['DISPATCH_SUITES']|Should -BeExactly '${{ inputs.suites }}'
        $called=& $invokePlanStep 'workflow_dispatch'
        ($called.Bound -join ',')|Should -BeExactly 'Event,OutputPath,Revision,Suite'
        $called.Event|Should -BeExactly 'workflow_dispatch'
        ($called.Suite -join ',')|Should -BeExactly 'Core,Git'
        $called.Revision|Should -BeExactly ('b'*40)
    }

    It 'plans <EventName> from the diff base, without a suite' -ForEach @(@{EventName='pull_request'},@{EventName='push'}) {
        $called=& $invokePlanStep $EventName
        ($called.Bound -join ',')|Should -BeExactly 'Base,Event,OutputPath,Revision'
        $called.Base|Should -BeExactly ('a'*40)
        $called.Event|Should -BeExactly $EventName
    }
}

Describe 'companions-ci.yml qualification ordering' {
    It 'starts product qualification only after a successful or skipped warm-up' {
        $products=$companions['jobs']['products']
        @($products['needs'])|Should -Contain 'images'
        $guard=[string]$products['if']
        foreach($clause in @('always()','!cancelled()',"needs.images.result == 'success' || needs.images.result == 'skipped'","needs.plan.result == 'success'","needs.source-checks.result == 'success'","needs.layout-tests.result == 'success'","needs.plan.outputs.run_products == 'true'")){
            $guard.Contains($clause)|Should -BeTrue -Because $clause
        }
    }

    It 'tells every per-suite call whether the warm-up owned the images' {
        [string]$companions['jobs']['products']['with']['images_prepared']|Should -BeExactly '${{ needs.images.result == ''success'' }}'
    }

    It 'reports the warm-up result to the required status' {
        @($companions['jobs']['ci-status']['needs'])|Should -Contain 'images'
    }
}

Describe 'companions-ci.yml script-only plans' {
    It 'exposes the plan output <Name> from the plan step' -ForEach @(
        @{Name='run_layout'},@{Name='tooling_scope'},@{Name='script_tests'},@{Name='script_mutation_targets'},@{Name='run_tooling'}
    ) {
        [string]$companions['jobs']['plan']['outputs'][$Name]|Should -BeExactly ('${{ steps.plan.outputs.'+$Name+' }}')
    }

    It 'runs the layout tests only when the plan asks for them' {
        $layout=$companions['jobs']['layout-tests']
        @($layout['needs']) -join ','|Should -BeExactly 'plan'
        [string]$layout['if']|Should -BeExactly 'needs.plan.outputs.run_layout == ''true'''
    }

    It 'starts the tooling after the layout tests, or without them only when the plan skipped them' {
        $tooling=$companions['jobs']['tooling-only']
        (@($tooling['needs'])|Sort-Object -CaseSensitive) -join ','|Should -BeExactly 'layout-tests,plan,source-checks'
        $guard=[string]$tooling['if']
        foreach($clause in @('always()','!cancelled()',"needs.plan.result == 'success'","needs.source-checks.result == 'success'","needs.layout-tests.result == 'success' || (needs.layout-tests.result == 'skipped' && needs.plan.outputs.run_layout == 'false')","needs.plan.outputs.run_tooling == 'true'")){
            $guard.Contains($clause)|Should -BeTrue -Because $clause
        }
        $guard|Should -Not -Match "needs\.layout-tests\.result == 'failure'"
    }

    It 'passes the planned selection <Name> to tooling-ci.yml' -ForEach @(
        @{Name='scope';Source='tooling_scope'},@{Name='script_tests';Source='script_tests'},@{Name='script_mutation_targets';Source='script_mutation_targets'}
    ) {
        $with=$companions['jobs']['tooling-only']['with']
        (@($with.Keys)|Sort-Object -CaseSensitive) -join ','|Should -BeExactly 'scope,script_mutation_targets,script_tests'
        [string]$with[$Name]|Should -BeExactly ('${{ needs.plan.outputs.'+$Source+' }}')
    }

    It 'keeps every product, smoke and distribution job behind the layout tests' -ForEach @(@{Job='products'},@{Job='smokes'},@{Job='distribution'}) {
        @($companions['jobs'][$Job]['needs'])|Should -Contain 'layout-tests'
    }
}

Describe 'ci.yml per-suite producer' {
    It 'declares images_prepared as an optional boolean defaulting to false' {
        $declared=$engine['on']['workflow_call']['inputs']['images_prepared']
        [string]$declared['type']|Should -BeExactly 'boolean'
        [string]$declared['required']|Should -BeExactly 'false'
        [string]$declared['default']|Should -BeExactly 'false'
    }

    It 'skips its producer when the caller prepared the images' {
        ([string]$producer['if']).Contains('!inputs.images_prepared')|Should -BeTrue
        ([string]$producer['if']).Contains("github.ref == 'refs/heads/develop'")|Should -BeTrue
    }

    It 'keeps a per-suite concurrency group for standalone calls' {
        [string]$producer['concurrency']['group']|Should -Match 'inputs\.suite'
        [string]$producer['concurrency']['group']|Should -Match 'matrix\.rid'
        [string]$producer['concurrency']['cancel-in-progress']|Should -BeExactly 'false'
    }

    It 'accepts a skipped producer before selecting Linux images' {
        ([string]$engine['jobs']['linux-selection']['if']).Contains("needs.linux-images.result == 'skipped'")|Should -BeTrue
    }
}
