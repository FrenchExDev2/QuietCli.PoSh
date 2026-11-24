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
    $ready=& $load 'quietcli2-readytorun.yml'
    $imageJob=(& $load 'linux-images.yml')['jobs']['prepare']
    $runs={param($Job)[string[]]@($Job['steps']|ForEach-Object {[string]$_['run']})}
    $stepIndex={param($Job,[scriptblock]$Match)
        $steps=@($Job['steps'])
        for($index=0;$index -lt $steps.Count;$index++){if(& $Match $steps[$index]){return $index}}
        -1
    }
}

Describe 'Core performance evidence on PR and develop' {
    It 'routes both automatic events through the same qualification and performance steps' {
        $companions['on'].ContainsKey('pull_request')|Should -BeTrue
        @($companions['on']['push']['branches'])|Should -Contain 'develop'
        $products=@($companions['jobs'].Values|Where-Object {[string]$_['uses'] -ceq './.github/workflows/ci.yml'})
        $products.Count|Should -Be 1
        [string]$products[0]['with']['collect_performance']|Should -BeExactly '${{ matrix.collect_performance }}'
        [string]$products[0]['if']|Should -Not -Match 'github.event_name.*push'
        $calls=(& $runs $engine['jobs']['windows']) -join "`n"
        $calls|Should -Match 'Invoke-GitHubCi.ps1'
        $calls|Should -Not -Match 'github.event_name'
        @($engine['jobs']['performance-results']['steps']|Where-Object {([string]$_['run']).Contains('New-CorePerformanceReport.ps1')}).Count|Should -Be 1
    }

    It 'keeps startup WhatIf inert without a manifest, executable or configuration directory' {
        $directory=[IO.Path]::Combine($TestDrive,'startup-preview')
        $probe=[IO.Path]::Combine($root,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Startup.Probe.ps1')
        $result=Invoke-QuietTestScript -ScriptPath $probe -ArgumentList @('-Manifest','missing.psd1','-Executable','missing.exe','-ConfigurationDirectory',$directory,'-MeasurePhases','-WhatIf') -TimeoutSeconds 60
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        Test-Path -LiteralPath $directory|Should -BeFalse
    }
}

Describe 'Shared Linux image production' {
    It 'selects the same native targets for production and qualification' {
        $rows=@($imageJob['strategy']['matrix']['include']|ForEach-Object {$_['rid']+'@'+$_['runner']}|Sort-Object)
        $rows -join ','|Should -BeExactly 'linux-arm64@ubuntu-24.04-arm,linux-musl-arm64@ubuntu-24.04-arm,linux-musl-x64@ubuntu-latest,linux-x64@ubuntu-latest'
        $definition=(& $runs $engine['jobs']['linux-matrix']) -join "`n"
        foreach($row in $rows){
            ($rid,$runner)=$row.Split('@')
            $definition|Should -Match ([regex]::Escape("rid='$rid';runner='$runner'"))
        }
    }

    It 'runs shared preparation for selected PR tests as well as develop' {
        @($warm['needs']) -join ','|Should -BeExactly 'plan,source-checks'
        [string]$warm['if']|Should -BeExactly "needs.plan.outputs.run_products == 'true' || needs.plan.outputs.run_readytorun == 'true'"
        [string]$warm['with']['suites_json']|Should -BeExactly '${{ needs.plan.outputs.image_suites }}'
        [string]$warm['with']['publish_cache']|Should -Match 'refs/heads/develop'
        [string]$warm['with']['publish_cache']|Should -Not -Match 'pull_request'
        [string]$warm['with']['artifact_scope']|Should -BeExactly 'workspace'
        [string]$companions['jobs']['plan']['outputs']['image_suites']|Should -BeExactly '${{ steps.plan.outputs.image_suites }}'
    }

    It 'publishes the bundle after archive generation' {
        $prepare=& $stepIndex $imageJob {param($step)([string]$step['run']).Contains('Export-CiImageBundle.ps1')}
        $upload=& $stepIndex $imageJob {param($step)$step['with'] -and ([string]$step['with']['name']).StartsWith('quietcli-prepared-images-')}
        $prepare|Should -BeGreaterOrEqual 0
        $upload|Should -BeGreaterThan $prepare
        [string]$imageJob['steps'][$upload]['with']['overwrite']|Should -BeExactly 'true'
        [string]$imageJob['steps'][$upload]['with']['if-no-files-found']|Should -BeExactly 'error'
    }

    It 'routes all three producer calls through the same implementation' {
        foreach($job in $warm,$producer,$ready['jobs']['linux-images']){
            [string]$job['uses']|Should -BeExactly './.github/workflows/linux-images.yml'
        }
    }

    It 'requires a published archive before each Linux consumer starts' {
        foreach($job in $engine['jobs']['linux-result'],$ready['jobs']['readytorun-linux']){
            @($job['needs'])|Should -Contain 'linux-images'
            [string]$job['if']|Should -Match "needs.linux-images.result == 'success'"
            [string]$job['if']|Should -Match "inputs.images_prepared && needs.linux-images.result == 'skipped'"
            $commands=(& $runs $job) -join "`n"
            $commands|Should -Match './scripts/Import-CiImageBundle.ps1'
            $commands|Should -Not -Match 'New-Ci(?:Suite)?Image\.ps1|QUIETCLI_REGISTRY_TOKEN'
            $download=& $stepIndex $job {param($step)$step['with'] -and ([string]$step['with']['name']).StartsWith('quietcli-prepared-images-')}
            $loadImage=& $stepIndex $job {param($step)([string]$step['run']).Contains('Import-CiImageBundle.ps1')}
            $download|Should -BeGreaterOrEqual 0
            $loadImage|Should -BeGreaterThan $download
        }
        @($companions['jobs']['readytorun']['needs'])|Should -Contain 'images'
        [string]$companions['jobs']['readytorun']['with']['images_prepared']|Should -BeExactly 'true'
    }
}

Describe 'companions-ci.yml manual qualification' {
    BeforeAll {
        $planStep=@($companions['jobs']['plan']['steps']|Where-Object {[string]$_['id'] -ceq 'plan'})[0]
        # Runs the production entry point against a stub that records the actual planner arguments.
        $invokePlanStep={param([string]$EventName)
            $directory=[IO.Path]::Combine($TestDrive,'plan-step-'+[guid]::NewGuid().ToString('N'))
            $null=New-QuietTestFile ([IO.Path]::Combine($directory,'scripts','New-CiImpactPlan.ps1')) @'
[CmdletBinding(SupportsShouldProcess)]
param([string]$Base,[string]$Revision,[string]$Event,[string[]]$Suite,[string]$OutputPath,[string]$PullRequestBody)
[IO.File]::WriteAllText($env:RECORDED_CALL,(ConvertTo-Json -Compress -InputObject ([ordered]@{Bound=@($PSBoundParameters.Keys|Where-Object {$_ -cne 'Confirm'}|Sort-Object);Base=$Base;Revision=$Revision;Event=$Event;Suite=@($Suite);Body=$PullRequestBody})))
'@
            Copy-Item -LiteralPath ([IO.Path]::Combine($root,'scripts','Invoke-GitHubCiPlan.ps1')) -Destination ([IO.Path]::Combine($directory,'scripts'))
            $step=[IO.Path]::Combine($directory,'step.ps1')
            $null=New-QuietTestFile $step ("Set-Location -LiteralPath `$PSScriptRoot`n"+[string]$planStep['run'])
            $output=[IO.Path]::Combine($directory,'called.json')
            $payloadPath=[IO.Path]::Combine($directory,'event.json')
            $data=@{before='a'*40;pull_request=@{number=42;body="Résumé`n~~~`n- [x] raw`n~~~";head=@{sha='c'*40};base=@{sha='a'*40}}}
            [IO.File]::WriteAllText($payloadPath,(ConvertTo-Json $data -Depth 5 -Compress))
            $run=Invoke-QuietTestScript -ScriptPath $step -Environment @{
                GITHUB_EVENT_NAME=$EventName;GITHUB_SHA=('b'*40);GITHUB_OUTPUT=[IO.Path]::Combine($directory,'outputs.txt')
                GITHUB_EVENT_PATH=$payloadPath;GITHUB_REF='refs/pull/42/merge';RECORDED_CALL=$output;DISPATCH_SUITES='Core,Git'
            } -TimeoutSeconds 120
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
        ($called.Bound -join ',')|Should -BeExactly $(if($EventName -ceq 'pull_request'){'Base,Event,OutputPath,PullRequestBody,Revision'}else{'Base,Event,OutputPath,Revision'})
        if($EventName -ceq 'pull_request'){$called.Body|Should -BeExactly "Résumé`n~~~`n- [x] raw`n~~~"}
        $called.Base|Should -BeExactly ('a'*40)
        $called.Event|Should -BeExactly $EventName
    }

    It 'replans edits and gates the strict ReadyToRun call' {
        $companions['on']['pull_request']['types'] | Should -Contain 'edited'
        $companions['jobs']['readytorun']['if'] | Should -BeExactly "needs.plan.outputs.run_readytorun == 'true'"
        $companions['jobs']['readytorun']['with']['require_complete'] | Should -Be 'true'
        $companions['jobs']['ci-status']['needs'] | Should -Contain 'readytorun'
        $companions['jobs']['products']['with']['run_preview'] | Should -BeExactly '${{ matrix.run_preview }}'
    }
}

Describe 'companions-ci.yml qualification ordering' {
    It 'starts product qualification only after successful image preparation' {
        $products=$companions['jobs']['products']
        @($products['needs'])|Should -Contain 'images'
        $guard=[string]$products['if']
        foreach($clause in @('always()','!cancelled()',"needs.images.result == 'success'","needs.plan.result == 'success'","needs.source-checks.result == 'success'","needs.layout-tests.result == 'success'","needs.plan.outputs.run_products == 'true'")){
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
        @{Name='run_layout'},@{Name='tooling_scope'},@{Name='script_tests'},@{Name='script_mutation_targets'},@{Name='script_mutation_no_input_cache'},@{Name='run_tooling'}
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
        (@($with.Keys)|Sort-Object -CaseSensitive) -join ','|Should -BeExactly 'mutation_parallel,scope,script_mutation_no_input_cache,script_mutation_targets,script_tests'
        [string]$with[$Name]|Should -BeExactly ('${{ needs.plan.outputs.'+$Source+' }}')
    }

    It 'passes the cache choice as a boolean to tooling' {
        $companions['jobs']['tooling-only']['with']['script_mutation_no_input_cache']|Should -BeExactly '${{ needs.plan.outputs.script_mutation_no_input_cache == ''true'' }}'
    }

    It 'consumes the companion checks matrix and makes its results required' {
        $job=$companions['jobs']['companion-checks']
        $job['strategy']['matrix']|Should -BeExactly '${{ fromJson(needs.plan.outputs.companion_checks) }}'
        $job['strategy']['max-parallel']|Should -BeExactly '${{ needs.plan.outputs.mutation_parallel == ''true'' && 6 || 1 }}'
        $job['with']['campaign']|Should -BeExactly '${{ matrix.campaign }}'
        $companions['jobs']['ci-status']['needs']|Should -Contain 'companion-checks'
    }

    It 'keeps every product, smoke and distribution job behind the layout tests' -ForEach @(@{Job='products'},@{Job='smokes'},@{Job='distribution'}) {
        @($companions['jobs'][$Job]['needs'])|Should -Contain 'layout-tests'
    }
}

Describe 'ci.yml Linux matrix resources' {
    It 'restores the pinned resource archives before resolving the companion catalogue' {
        $job=$engine['jobs']['linux-matrix']
        $cacheIndex=& $stepIndex $job {param($step)$step['uses'] -ceq './.github/actions/cache-resources'}
        $matrixIndex=& $stepIndex $job {param($step)$step['id'] -ceq 'matrix'}
        $cacheIndex|Should -BeGreaterOrEqual 0
        $cacheIndex|Should -BeLessThan $matrixIndex
        $job['steps'][$matrixIndex]['run']|Should -Match 'Initialize-CiCompanions.ps1'
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
        ([string]$producer['with']['publish_cache']).Contains("github.ref == 'refs/heads/develop'")|Should -BeTrue
    }

}
