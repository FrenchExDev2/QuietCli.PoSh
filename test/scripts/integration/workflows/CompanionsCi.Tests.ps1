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
        [string]$warm['if']|Should -BeExactly "needs.plan.outputs.run_products == 'true' || needs.plan.outputs.run_readytorun == 'true' || needs.plan.outputs.renew_image_caches == 'true'"
        [string]$warm['with']['suites_json']|Should -BeExactly '${{ needs.plan.outputs.image_suites }}'
        [string]$warm['with']['publish_cache']|Should -Match 'refs/heads/develop'
        [string]$warm['with']['publish_cache']|Should -Not -Match 'pull_request'
        [string]$warm['with']['artifact_scope']|Should -BeExactly 'workspace'
        [string]$warm['with']['renew_cache']|Should -BeExactly '${{ needs.plan.outputs.renew_image_caches == ''true'' }}'
        [string]$companions['jobs']['plan']['outputs']['image_suites']|Should -BeExactly '${{ steps.plan.outputs.image_suites }}'
    }

    It 'publishes the bundle after archive generation' {
        $prepare=& $stepIndex $imageJob {param($step)$step['name'] -ceq 'Prepare and archive the selected image chains'}
        $upload=& $stepIndex $imageJob {param($step)$step['with'] -and ([string]$step['with']['name']).StartsWith('quietcli-prepared-images-')}
        $prepare|Should -BeGreaterOrEqual 0
        $upload|Should -BeGreaterThan $prepare
        [string]$imageJob['steps'][$upload]['with']['overwrite']|Should -BeExactly 'true'
        [string]$imageJob['steps'][$upload]['with']['if-no-files-found']|Should -BeExactly 'error'
        [string]$imageJob['steps'][$upload]['with']['path']|Should -Match 'cache-matched-key.*registry-hit.*images.tar'
    }

    It 'starts Docker on an archive miss and saves a new archive only after a local build' {
        $key=& $stepIndex $imageJob {param($step)$step['id'] -ceq 'image_key'}
        $cache=& $stepIndex $imageJob {param($step)$step['id'] -ceq 'image_cache'}
        $docker=& $stepIndex $imageJob {param($step)$step['uses'] -ceq './.github/actions/cache-ci-layers' -and $step['with']['mode'] -ceq 'restore'}
        $prepare=& $stepIndex $imageJob {param($step)$step['name'] -ceq 'Prepare and archive the selected image chains'}
        $reuse=& $stepIndex $imageJob {param($step)([string]$step['run']).Contains('-ReuseArchive')}
        $save=& $stepIndex $imageJob {param($step)$step['name'] -ceq 'Save the exact final image archive'}
        $key | Should -BeGreaterOrEqual 0
        $cache | Should -BeGreaterThan $key
        $docker | Should -BeGreaterThan $cache
        $prepare | Should -BeGreaterThan $docker
        $reuse | Should -BeGreaterThan $prepare
        $save | Should -BeGreaterThan $reuse
        $steps=$imageJob['steps']
        $steps[$key]['run'] | Should -Match '-CacheKey'
        $steps[$cache]['with']['key'] | Should -BeExactly '${{ steps.image_key.outputs.key }}-lookup'
        $steps[$cache]['with']['restore-keys'].Trim() -split '\r?\n' | Should -BeExactly @('${{ steps.image_key.outputs.key }}-renew-','${{ steps.image_key.outputs.key }}')
        $steps[$cache]['if'] | Should -BeExactly '${{ !inputs.images_only && !inputs.renew_cache }}'
        $steps[$docker]['if'] | Should -BeExactly '${{ !inputs.renew_cache && (inputs.images_only || !steps.image_cache.outputs.cache-matched-key) }}'
        $steps[$prepare]['id'] | Should -BeExactly 'prepare_bundle'
        $steps[$prepare]['if'] | Should -BeExactly '${{ !inputs.images_only && !steps.image_cache.outputs.cache-matched-key }}'
        $steps[$prepare]['run'] | Should -Match '-RenewCache:.*-TransferRegistryReferences -PassThru'
        $steps[$reuse]['if'] | Should -BeExactly '${{ !inputs.images_only && steps.image_cache.outputs.cache-matched-key }}'
        $steps[$reuse]['env']['ARCHIVE_CACHE_KEY'] | Should -BeExactly '${{ steps.image_cache.outputs.cache-matched-key }}'
        $steps[$save]['if'] | Should -BeExactly '${{ steps.prepare_bundle.outputs.registry-hit == ''false'' }}'
        $steps[$save]['with']['path'] | Should -BeExactly $steps[$cache]['with']['path']
        $steps[$save]['with']['key'] | Should -BeExactly '${{ inputs.renew_cache && format(''{0}-renew-{1}-{2}'', steps.image_key.outputs.key, github.run_id, github.run_attempt) || steps.image_key.outputs.key }}'
    }

    It 'saves BuildKit layers only for a missed primary key with changed nonempty indexes' {
        $steps=$imageJob['steps']
        $restore=& $stepIndex $imageJob {param($step)$step['id'] -ceq 'layer_cache'}
        $save=& $stepIndex $imageJob {param($step)$step['uses'] -ceq './.github/actions/cache-ci-layers' -and $step['with']['mode'] -ceq 'save'}
        $restore|Should -BeGreaterOrEqual 0
        $save|Should -BeGreaterThan $restore
        $steps[$restore]['with']['mode']|Should -BeExactly 'restore'
        $steps[$save]['with']['key']|Should -BeExactly '${{ steps.layer_cache.outputs.cache-primary-key }}'
        $condition=$steps[$save]['if']
        $condition|Should -Match ([regex]::Escape("steps.layer_cache.outcome == 'success' && steps.layer_cache.outputs.cache-hit != 'true'"))
        $condition|Should -Match ([regex]::Escape("hashFiles('.cache/ci-buildkit/*/index.json') != ''"))
        $condition|Should -Match ([regex]::Escape("hashFiles('.cache/ci-buildkit/*/index.json') != steps.layer_cache.outputs.restored-indexes"))
        $action=$parser.Deserialize([IO.File]::ReadAllText([IO.Path]::Combine($root,'.github','actions','cache-ci-layers','action.yml'),[Text.Encoding]::UTF8))
        $action['outputs']['cache-primary-key']['value']|Should -BeExactly '${{ steps.restore.outputs.cache-primary-key }}'
        $action['outputs']['cache-hit']['value']|Should -BeExactly '${{ steps.restore.outputs.cache-hit }}'
        $action['outputs']['restored-indexes']['value']|Should -BeExactly '${{ steps.enable.outputs.restored-indexes }}'
        $action['runs']['steps'][2]['env']['RESTORED_INDEXES']|Should -BeExactly '${{ hashFiles(''.cache/ci-buildkit/*/index.json'') }}'
    }

    It 'keys the archive by its unique native image plans, independently of suite order and aliases' {
        $export=[IO.Path]::Combine($root,'scripts','Export-CiImageBundle.ps1')
        $probe=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'image-key.ps1')) @'
$ErrorActionPreference='Stop'
@{
    Core=(& $env:IMAGE_EXPORT_SCRIPT -Suite Core -RuntimeIdentifier linux-x64 -CacheKey)
    WithAlias=(& $env:IMAGE_EXPORT_SCRIPT -Suite Core,Vagrant -RuntimeIdentifier linux-x64 -CacheKey)
    Alpine=(& $env:IMAGE_EXPORT_SCRIPT -Suite Core -RuntimeIdentifier linux-musl-x64 -CacheKey)
    CoreAndGit=(& $env:IMAGE_EXPORT_SCRIPT -Suite Core,Git -RuntimeIdentifier linux-x64 -CacheKey)
    Reordered=(& $env:IMAGE_EXPORT_SCRIPT -Suite Git,Core,Core -RuntimeIdentifier linux-x64 -CacheKey)
} | ConvertTo-Json -Compress
'@
        $result=Invoke-QuietTestScript -ScriptPath $probe -Environment @{IMAGE_EXPORT_SCRIPT=$export}
        $result.ExitCode | Should -Be 0 -Because $result.Error
        $keys=$result.Output | ConvertFrom-Json
        $keys.Core | Should -Match '\A[0-9a-f]{64}\z'
        $keys.WithAlias | Should -BeExactly $keys.Core
        $keys.Alpine | Should -Not -BeExactly $keys.Core
        $keys.CoreAndGit | Should -Not -BeExactly $keys.Core
        $keys.Reordered | Should -BeExactly $keys.CoreAndGit
    }

    It 'previews archive reuse without opening a receipt or creating the archive directory' {
        $export=[IO.Path]::Combine($root,'scripts','Export-CiImageBundle.ps1')
        $directory=[IO.Path]::Combine($TestDrive,'cache-preview')
        $arguments=@('-Suite','Core','-RuntimeIdentifier','linux-x64','-OutputDirectory',$directory,'-Revision',('e'*40),'-RunId','315','-ReuseArchive','-WhatIf')
        $result=Invoke-QuietTestScript -ScriptPath $export -ArgumentList $arguments
        $result.ExitCode | Should -Be 0 -Because $result.Error
        Test-Path -LiteralPath $directory | Should -BeFalse
    }

    It 'hands off a verified renewed cache key without moving the archive or accepting another run' {
        $export=[IO.Path]::Combine($root,'scripts','Export-CiImageBundle.ps1')
        $import=[IO.Path]::Combine($root,'scripts','Import-CiImageBundle.ps1')
        $planner=[IO.Path]::Combine($root,'scripts','New-CiSuiteImage.ps1')
        $probe=New-QuietTestFile ([IO.Path]::Combine($TestDrive,'archive-receipt-identity.ps1')) @'
$ErrorActionPreference='Stop'
$plan=& $env:PLAN_SCRIPT -Suite Core -RuntimeIdentifier linux-x64 -PlanOnly
@{Fingerprint=$plan.Fingerprint;ArchiveKey=(& $env:EXPORT_SCRIPT -Suite Core -RuntimeIdentifier linux-x64 -CacheKey)} | ConvertTo-Json
'@
        $identity=Invoke-QuietTestScript -ScriptPath $probe -Environment @{PLAN_SCRIPT=$planner;EXPORT_SCRIPT=$export}
        $identity.ExitCode|Should -Be 0 -Because $identity.Error
        $ids=$identity.Output | ConvertFrom-Json
        $key="quietcli-ci-archive-v1-linux-x64-$($ids.ArchiveKey)-renew-315-2"
        $directory=[IO.Path]::Combine($TestDrive,'restored-archive')
        $archive=New-QuietTestFile ([IO.Path]::Combine($directory,'images.tar')) 'Fixture image archive'
        $receipt=@{SchemaVersion=2;Revision=('a'*40);RunId='314';RuntimeIdentifier='linux-x64';ArchiveSha256=(Get-FileHash -LiteralPath $archive).Hash;Fingerprints=@($ids.Fingerprint)}
        $null=New-QuietTestFile ([IO.Path]::Combine($directory,'bundle.json')) (ConvertTo-Json $receipt)
        $arguments=@('-Suite','Core','-RuntimeIdentifier','linux-x64','-OutputDirectory',$directory,'-Revision',('e'*40),'-RunId','315','-ReuseArchive','-RestoredCacheKey',$key)
        $result=Invoke-QuietTestScript -ScriptPath $export -ArgumentList $arguments
        $result.ExitCode|Should -Be 0 -Because $result.Error
        $handoff=[IO.Path]::Combine($TestDrive,'receipt-only')
        foreach($name in 'bundle.json','handoff.json'){
            $null=New-QuietTestFile ([IO.Path]::Combine($handoff,$name)) (Get-Content -LiteralPath ([IO.Path]::Combine($directory,$name)) -Raw -Encoding utf8)
        }
        $read=@('-Suite','Core','-RuntimeIdentifier','linux-x64','-Directory',$handoff,'-Revision',('e'*40),'-GetCacheKey','-RunId')
        $current=Invoke-QuietTestScript -ScriptPath $import -ArgumentList ($read+@('315'))
        $current.ExitCode|Should -Be 0 -Because $current.Error
        $current.Output.Trim()|Should -BeExactly $key
        $stale=Invoke-QuietTestScript -ScriptPath $import -ArgumentList ($read+@('316'))
        $stale.ExitCode|Should -Not -Be 0
        $stale.Error|Should -Match 'CiImageHandoffIdentityMismatch'
    }

    It 'hands off registry digests without a Docker build and bypasses the registry for a renewal' {
        $fixture=[IO.Path]::Combine($TestDrive,'image-preparation')
        $scripts=[IO.Path]::Combine($fixture,'scripts')
        $lib=[IO.Path]::Combine($scripts,'lib')
        [void][IO.Directory]::CreateDirectory($lib)
        Copy-Item -LiteralPath ([IO.Path]::Combine($root,'scripts','Export-CiImageBundle.ps1')) -Destination $scripts
        Copy-Item -LiteralPath ([IO.Path]::Combine($root,'scripts','lib','WorkspaceJson.psm1')) -Destination ([IO.Path]::Combine($lib,'Common.psm1'))
        $null=New-QuietTestFile ([IO.Path]::Combine($lib,'CiCompanions.psm1')) @'
function Read-QuietCiCompanions { param($WorkspaceRoot) @{} }
function Invoke-QuietCiSuiteImages {
    [CmdletBinding(SupportsShouldProcess)]
    param($WorkspaceRoot,$Configuration,$Suite,$RuntimeIdentifier,$ContainerRuntime,[switch]$RegistryCache,[switch]$PublishCache,[switch]$ProbeOnly)
    if($env:EXPECT_RENEW -ceq 'true'){
        if($RegistryCache -or $ProbeOnly -or $PublishCache){throw 'Renewal used the registry'}
        return [pscustomobject]@{CacheHit=$false;Chains=@()}
    }
    if(!$RegistryCache -or !$ProbeOnly){throw 'A verified registry image should require only a metadata probe'}
    [pscustomobject]@{CacheHit=$true;Chains=@([pscustomobject]@{Receipt=[pscustomobject]@{Fingerprint=('f'*64);RegistryDigest=('sha256:'+('a'*64))}})}
}
'@
        $null=New-QuietTestFile ([IO.Path]::Combine($lib,'CiImages.psm1')) @'
function Export-QuietCiImageBundle {
    param($WorkspaceRoot,$RuntimeIdentifier,$Directory,$Revision,$RunId,$Receipts)
    [void][IO.Directory]::CreateDirectory($Directory)
    [IO.File]::WriteAllText([IO.Path]::Combine($Directory,'images.tar'),'Built archive',[Text.Encoding]::UTF8)
}
'@
        $export=[IO.Path]::Combine($scripts,'Export-CiImageBundle.ps1')
        $arguments=@('-Suite','Core','-RuntimeIdentifier','linux-x64','-Revision',('e'*40),'-RunId','315','-TransferRegistryReferences')
        $registry=[IO.Path]::Combine($fixture,'registry')
        $reused=Invoke-QuietTestScript -ScriptPath $export -ArgumentList ($arguments+@('-OutputDirectory',$registry)) -Environment @{EXPECT_RENEW='false'}
        $reused.ExitCode|Should -Be 0 -Because $reused.Error
        @(Get-ChildItem -LiteralPath $registry -Name)|Should -BeExactly @('handoff.json')
        $handoff=Get-Content -LiteralPath ([IO.Path]::Combine($registry,'handoff.json')) -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
        $handoff.RegistryDigests[('f'*64)]|Should -BeExactly ('sha256:'+('a'*64))
        $fresh=[IO.Path]::Combine($fixture,'renewed')
        $renewed=Invoke-QuietTestScript -ScriptPath $export -ArgumentList ($arguments+@('-OutputDirectory',$fresh,'-RenewCache')) -Environment @{EXPECT_RENEW='true'}
        $renewed.ExitCode|Should -Be 0 -Because $renewed.Error
        @(Get-ChildItem -LiteralPath $fresh -Name)|Should -BeExactly @('images.tar')
    }

    It 'routes all three producer calls through the same implementation' {
        foreach($job in $warm,$producer,$ready['jobs']['linux-images']){
            [string]$job['uses']|Should -BeExactly './.github/workflows/linux-images.yml'
        }
    }

    It 'requires a verified producer handoff before each Linux consumer starts' {
        foreach($job in $engine['jobs']['linux-result'],$ready['jobs']['readytorun-linux']){
            @($job['needs'])|Should -Contain 'linux-images'
            [string]$job['if']|Should -Match "needs.linux-images.result == 'success'"
            [string]$job['if']|Should -Match "inputs.images_prepared && needs.linux-images.result == 'skipped'"
            $commands=(& $runs $job) -join "`n"
            $commands|Should -Not -Match 'New-Ci(?:Suite)?Image\.ps1|QUIETCLI_REGISTRY_TOKEN'
            $load=& $stepIndex $job {param($step)$step['uses'] -ceq './.github/actions/load-ci-image-bundle'}
            $load|Should -BeGreaterOrEqual 0
            $job['steps'][$load]['with']['rid']|Should -BeExactly '${{ matrix.rid }}'
        }
        $action=$parser.Deserialize([IO.File]::ReadAllText([IO.Path]::Combine($root,'.github','actions','load-ci-image-bundle','action.yml'),[Text.Encoding]::UTF8))
        $restore=@($action['runs']['steps']|Where-Object {$_['uses'] -like 'actions/cache/restore@*'})
        $restore.Count|Should -Be 1
        $restore[0]['with']['key']|Should -BeExactly '${{ steps.key.outputs.cache-key }}'
        $restore[0]['with']['fail-on-cache-miss']|Should -BeExactly 'true'
        $restore[0]['with'].ContainsKey('restore-keys')|Should -BeFalse
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
        $companions['jobs']['readytorun']['if'] | Should -Match "needs.plan.outputs.run_readytorun == 'true'"
        $companions['jobs']['readytorun']['with']['require_complete'] | Should -Be 'true'
        $companions['jobs']['ci-status']['needs'] | Should -Contain 'readytorun'
        $companions['jobs']['products']['with']['run_preview'] | Should -BeExactly '${{ matrix.run_preview }}'
    }

    It 'retains ReadyToRun reports after either comparison outcome and leaves build failures to diagnostics' {
        foreach ($job in $ready['jobs']['readytorun'],$ready['jobs']['readytorun-linux']) {
            $steps = @($job['steps'])
            $comparison = @($steps | Where-Object { $_['id'] -ceq 'comparison' })
            $comparison.Count | Should -Be 1
            $comparison[0]['run'] | Should -Match 'REQUIRE_COMPLETE'
            $comparison[0]['run'] | Should -Match 'ReadyToRunComparisonMissing'
            $reports = @($steps | Where-Object { $_['with'] -and $_['with']['path'] -like 'artifacts/coldstart*' })
            $reports.Count | Should -Be 1
            $reports[0]['if'] | Should -BeExactly "`${{ !cancelled() && (steps.comparison.outcome == 'success' || steps.comparison.outcome == 'failure') }}"
            $reports[0]['with']['if-no-files-found'] | Should -BeExactly 'warn'
        }
    }

    It 'restores the pinned Core resources before building either benchmark variant' {
        foreach ($job in 'readytorun','readytorun-linux') {
            $steps = @($ready['jobs'][$job]['steps'])
            $restore = @($steps | Where-Object { [string]$_['run'] -match '^\./scripts/Initialize-Workspace\.ps1 -Restore\s*$' })
            $restore.Count | Should -Be 1
            $restore[0]['if'] | Should -BeNullOrEmpty
            $builds = @($steps | Where-Object { [string]$_['run'] -match '\./scripts/(Build-Workspace|New-ReadyToRunCandidate)\.ps1' })
            $builds.Count | Should -Be 2
            foreach ($build in $builds) {
                [Array]::IndexOf($steps, $restore[0]) | Should -BeLessThan ([Array]::IndexOf($steps, $build))
            }
        }
    }

    It 'uses direct A/B for PR qualification and offers A/A explicitly on manual dispatch' {
        $manual = $ready['on']['workflow_dispatch']['inputs']['aa_control']
        [string]$manual['type'] | Should -BeExactly 'boolean'
        [string]$manual['default'] | Should -BeExactly 'false'
        [string]$ready['on']['workflow_call']['inputs']['aa_control']['default'] | Should -BeExactly 'false'
        $companions['jobs']['readytorun']['with'].ContainsKey('aa_control') | Should -BeFalse
        foreach ($job in $ready['jobs']['readytorun'], $ready['jobs']['readytorun-linux']) {
            $comparison = $job['steps'] | Where-Object { $_['id'] -ceq 'comparison' }
            [string]$comparison['env']['AA_CONTROL'] | Should -BeExactly '${{ inputs.aa_control }}'
            $comparison['run'] | Should -Match ([regex]::Escape('-SkipAaControl:($env:AA_CONTROL -cne ''true'')'))
            $comparison['run'] | Should -Match 'if \(\$env:REQUIRE_COMPLETE -ceq ''true''\) \{ throw \}'
        }
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
        @{Name='run_layout'},@{Name='tooling_scope'},@{Name='script_tests'},@{Name='script_mutation_targets'},@{Name='script_mutation_no_input_cache'},@{Name='run_tooling'},
        @{Name='run_shared_build'},@{Name='tooling_requires_build'}
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
        (@($tooling['needs'])|Sort-Object -CaseSensitive) -join ','|Should -BeExactly 'build,layout-tests,plan,source-checks'
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
        (@($with.Keys)|Sort-Object -CaseSensitive) -join ','|Should -BeExactly 'build_artifact,mutation_parallel,scope,script_mutation_no_input_cache,script_mutation_targets,script_tests'
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

Describe 'Shared PR build artifact' {
    It 'compiles once on a cache miss and uploads an immutable artifact on either path' {
        $job=$companions['jobs']['build']
        $steps=@($job['steps'])
        $build=$steps|Where-Object {$_['run'] -match '\./scripts/Build-Workspace\.ps1'}
        @($build).Count|Should -Be 1
        $build['if']|Should -BeExactly "steps.build_cache.outputs.cache-hit != 'true'"
        $cache=$steps|Where-Object {$_['id'] -ceq 'build_cache'}
        $cache['with']['key']|Should -Match 'github\.sha'
        $cache['with'].ContainsKey('restore-keys')|Should -BeFalse
        $job['outputs']['artifact']|Should -BeExactly '${{ steps.upload.outputs.artifact-id }}'
        $verify=& $stepIndex $job {param($step)$step['run'] -match 'Sync-CiBuildArtifact.ps1 -Mode Verify'}
        $upload=& $stepIndex $job {param($step)$step['id'] -ceq 'upload'}
        $verify|Should -BeGreaterOrEqual 0
        $verify|Should -BeLessThan $upload
        $steps[$upload]['if']|Should -BeNullOrEmpty
        $companions['jobs']['ci-status']['needs']|Should -Contain 'build'
    }

    It 'passes the producer ID to each consumer instead of letting a PR fall back to compilation' {
        foreach($name in 'products','smokes','tooling-only','companion-checks','distribution','readytorun'){
            $job=$companions['jobs'][$name]
            $job['needs']|Should -Contain 'build'
            $job['with']['build_artifact']|Should -BeExactly '${{ needs.build.outputs.artifact }}'
            $job['if']|Should -Match "needs\.build\.outputs\.artifact != ''"
        }
        foreach($name in 'windows','linux-result'){
            $steps=@($engine['jobs'][$name]['steps'])
            ($steps|Where-Object {$_['run'] -match 'Build-Workspace\.ps1.*-ReuseVerifiedBuild'})['if']|Should -BeExactly "inputs.build_artifact == ''"
            ($steps|Where-Object {$_['run'] -match 'Build-Workspace\.ps1 -RequireVerifiedBuild'})['if']|Should -BeExactly "inputs.build_artifact != ''"
        }
    }
}
