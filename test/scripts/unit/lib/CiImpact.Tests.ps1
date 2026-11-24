#requires -Version 7.6

Describe 'Add-QuietCiPullRequestSelection companion campaigns' {
    BeforeAll {
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
        $null=Import-QuietTestLibrary -Name CiImpact
    }
    It 'uses the catalogue for a new companion and selects mutation and profiling independently' {
        Mock Read-QuietCiCompanions -ModuleName CiImpact {
            @{Companions=[ordered]@{
                Box2=[pscustomobject]@{Name='Box2';Mutation=@{environment=@{QUIETCLI_BOX_MUTATION='1'}}}
                Demo=[pscustomobject]@{Name='Demo';Mutation=$null}
            }}
        }
        $plan=[pscustomobject]@{RunTooling=$false;FullSuites=@();Reasons=@()}
        Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $TestDrive -Options @('run-profile-mutation-box2','profiling-demo','mutation-serial','script-mutation')
        $plan.MutationParallel|Should -BeFalse
        $plan.RunAllScriptMutations|Should -BeTrue
        $plan.ScriptMutationNoInputCache|Should -BeFalse
        $plan.RenewImageCaches|Should -BeFalse
        $plan.CompanionChecks.suite|Should -BeExactly @('Box2','Demo')
        $plan.CompanionChecks.campaign|Should -BeExactly @('mutation','profiling')
        $plan.FullSuites.Count|Should -Be 0
        $plan.RunTooling|Should -BeFalse
        $plan.RunPreview|Should -BeFalse
        $plan.RunReadyToRun|Should -BeFalse
        $plan.PullRequestOptions|Should -BeExactly @('run-profile-mutation-box2','profiling-demo','mutation-serial','script-mutation')
        $plan.Reasons.Companion|Should -BeExactly @('Box2','Demo','Mutations','Scripts')
    }

    It 'selects Linux image renewal without adding product or tooling qualification' {
        $plan=[pscustomobject]@{RunProducts=$false;RunTooling=$false;FullSuites=@();Reasons=@()}
        Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $TestDrive -Options @('renew-images-caches')
        $plan.RenewImageCaches|Should -BeTrue
        $plan.RunProducts|Should -BeFalse
        $plan.RunTooling|Should -BeFalse
        $plan.FullSuites.Count|Should -Be 0
        $plan.Reasons.Count|Should -Be 1
        $plan.Reasons[0].Companion|Should -BeExactly 'Linux images'
        $plan.Reasons[0].Action|Should -BeExactly 'renew-images-caches'
    }

    It 'bypasses cache input without adding any mutation targets' {
        $plan=[pscustomobject]@{RunTooling=$false;FullSuites=@();Reasons=@()}
        Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $TestDrive -Options @('script-mutation-no-input-cache')
        $plan.ScriptMutationNoInputCache|Should -BeTrue
        $plan.RunAllScriptMutations|Should -BeFalse
        $plan.RunTooling|Should -BeFalse
        $plan.MutationParallel|Should -BeTrue
        $plan.Reasons.Companion|Should -BeExactly 'Scripts'
        $plan.Reasons.Action|Should -BeExactly 'script-mutation-no-input-cache'
    }

    It 'schedules performance independently of profiling and mutation on the selected companion' {
        Mock Read-QuietCiCompanions -ModuleName CiImpact {
            @{Companions=[ordered]@{Git=[pscustomobject]@{Name='Git';Mutation=@{environment=@{QUIETCLI_GIT_MUTATION='1'}}};Demo=[pscustomobject]@{Name='Demo'}}}
        }
        $plan=[pscustomobject]@{RunTooling=$false;FullSuites=@();Reasons=@()}
        Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $TestDrive -Options @('performance-git','profiling-git','run-profile-mutation-git','performance-demo')
        $plan.CompanionChecks.suite|Should -BeExactly @('Git','Git','Demo')
        $plan.CompanionChecks.campaign|Should -BeExactly @('performance','profiled-mutation','performance')
        $plan.Reasons.Companion|Should -BeExactly @('Git','Git','Git','Demo')
        $plan.FullSuites.Count|Should -Be 0
    }

    It 'rejects a mutation option on a companion without a mutation campaign' {
        Mock Read-QuietCiCompanions -ModuleName CiImpact {
            @{Companions=[ordered]@{Demo=[pscustomobject]@{Name='Demo';Mutation=$null}}}
        }
        $plan=[pscustomobject]@{RunTooling=$false;FullSuites=@();Reasons=@()}
        {Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $TestDrive -Options @('run-profile-mutation-demo')} |
            Should -Throw '*CiCompanionNotAvailable: demo (Mutation)*'
    }

    It 'profiles the actual mutation pass when both options select the same companion' {
        Mock Read-QuietCiCompanions -ModuleName CiImpact {
            @{Companions=[ordered]@{Box2=[pscustomobject]@{Name='Box2';Mutation=@{environment=@{QUIETCLI_BOX_MUTATION='1'}}}}}
        }
        $plan=[pscustomobject]@{RunTooling=$false;FullSuites=@();Reasons=@()}
        Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $TestDrive -Options @('profiling-box2','run-profile-mutation-box2')
        $plan.CompanionChecks.Count|Should -Be 1
        $plan.CompanionChecks[0].suite|Should -BeExactly 'Box2'
        $plan.CompanionChecks[0].campaign|Should -BeExactly 'profiled-mutation'
        $plan.MutationParallel|Should -BeTrue
    }

    It 'covers Core mutation once when Tooling already runs it, but keeps profiled mutation and other companions' {
        Mock Read-QuietCiCompanions -ModuleName CiImpact {
            @{Companions=[ordered]@{
                Core=[pscustomobject]@{Name='Core';Mutation=@{suite='RunProfilesMutation'}}
                Git=[pscustomobject]@{Name='Git';Mutation=@{environment=@{QUIETCLI_GIT_MUTATION='1'}}}
            }}
        }
        $options=@('mutation','run-profile-mutation-core','run-profile-mutation-git','readytorun')
        $plan=[pscustomobject]@{RunTooling=$false;FullSuites=@();Reasons=@([pscustomobject]@{Input='original'})}
        Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $TestDrive -Options $options
        $plan.RunTooling|Should -BeTrue
        $plan.RunReadyToRun|Should -BeTrue
        $plan.CompanionChecks.suite|Should -BeExactly 'Git'
        $plan.CompanionChecks.campaign|Should -BeExactly 'mutation'
        $plan.Reasons[0].Input|Should -BeExactly 'original'
        $optionsReasons=@($plan.Reasons|Select-Object -Skip 1)
        $optionsReasons.Companion|Should -BeExactly @('Tooling','Core','Git','ReadyToRun')
        $optionsReasons.Action|Should -BeExactly $options
        foreach($reason in $optionsReasons){
            $reason.Input|Should -BeExactly 'pull_request.body'
            $reason.Reason|Should -BeExactly 'RequestedByPullRequestChecklist'
        }
        $profiled=[pscustomobject]@{RunTooling=$true;FullSuites=@();Reasons=@()}
        Add-QuietCiPullRequestSelection -Plan $profiled -WorkspaceRoot $TestDrive -Options @('run-profile-mutation-core','profiling-core')
        $profiled.CompanionChecks.campaign|Should -BeExactly 'profiled-mutation'
    }

    It 'requires Preview qualification exactly once and recomputes the dependent smokes <Case>' -ForEach @(
        @{Case='on its own';Existing=@();Options=@('preview');Full=@('Core');Smokes=@('Git','Demo');Suite='Core';Reads=1}
        @{Case='alongside an existing suite';Existing=@('Git');Options=@('profiling-git','preview');Full=@('Core','Git');Smokes=@('Demo');Suite='Selected';Reads=1}
        @{Case='with Core already qualified';Existing=@('Core');Options=@('preview');Full=@('Core');Smokes=@('Demo','Git');Suite='Core';Reads=0}
    ) {
        Mock Read-QuietCiCompanions -ModuleName CiImpact {
            @{Base='Core';Companions=[ordered]@{
                Core=[pscustomobject]@{Name='Core';Image='base';requires=@();Mutation=@{suite='RunProfilesMutation'}}
                Git=[pscustomobject]@{Name='Git';Image='overlay';requires=@('Core');Mutation=$null}
                Demo=[pscustomobject]@{Name='Demo';Image='none';requires=@('Git');Mutation=$null}
            };Suites=[ordered]@{
                Core=@{Group='Core';Requires=@('Core')}
                Git=@{Group='Git';Requires=@('Git')}
                Demo=@{Group='Demo';Requires=@('Demo')}
            }}
        }
        $plan=[pscustomobject]@{RunTooling=$false;FullSuites=$Existing;SelectedSuites=$Existing;RunProducts=($Reads -eq 0);Suite=$(if($Reads -eq 0){'Core'}else{'None'});SmokeSuites=$(if($Reads -eq 0){$Smokes}else{@()});Reasons=@()}
        Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $TestDrive -Options $Options
        $plan.RunPreview|Should -BeTrue
        $plan.RunProducts|Should -BeTrue
        $plan.FullSuites|Should -BeExactly $Full
        $plan.SelectedSuites|Should -BeExactly $Full
        @($plan.SmokeSuites)|Should -BeExactly @($Smokes|Sort-Object)
        $plan.Suite|Should -BeExactly $Suite
        $plan.Reasons[-1].Companion|Should -BeExactly 'Core'
        Should -Invoke Read-QuietCiCompanions -ModuleName CiImpact -Exactly -Times $Reads
    }

    It 'fails explicitly when Preview cannot select Core' {
        Mock Read-QuietCiCompanions -ModuleName CiImpact { @{Companions=[ordered]@{Demo=@{Name='Demo'}}} }
        $plan=[pscustomobject]@{RunTooling=$false;FullSuites=@();Reasons=@()}
        {Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $TestDrive -Options preview}|Should -Throw '*CiPreviewCoreUnavailable*'
    }
}
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','CiFixtures.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name CiImpact
    $seed=Get-QuietTestSeed

    $newCatalogue={param([Random]$Random)New-QuietCiCatalogue $Random}
    $ownedPath={param([Random]$Random,$Catalogue,[string]$Companion)Get-QuietCiOwnedPath $Random $Catalogue $Companion}
    # Independent oracle: companions outside Selected whose transitive requirements reach Selected.
    $expectedSmokes={param($Catalogue,[string[]]$Selected)
        $map=$Catalogue.Configuration.Companions
        @(foreach($name in $map.Keys){
            if($name -cin $Selected){continue}
            $seen=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$stack=[Collections.Generic.Stack[string]]::new()
            foreach($dependency in $map[$name].requires){$stack.Push($dependency)}
            while($stack.Count){$current=$stack.Pop();if($seen.Add($current)){foreach($dependency in $map[$current].requires){$stack.Push($dependency)}}}
            if(@($seen|Where-Object {$_ -cin $Selected}).Count){$name}
        })|Sort-Object
    }
    $impact={param($Catalogue,[string[]]$Paths)
        $script:catalogue=$Catalogue
        Get-QuietCiImpact -WorkspaceRoot $TestDrive -ChangedPaths $Paths
    }
}

Describe 'Get-QuietCiImpact' {
    BeforeEach {
        Mock -ModuleName CiImpact Read-QuietCiCompanions { $script:catalogue.Configuration }
        Mock -ModuleName CiImpact Get-QuietWorkspaceProjects { $script:catalogue.Modules }
        Mock -ModuleName CiImpact Get-QuietCiProjectGraph { @() }
    }

    It 'selects exactly the owners of the changed paths and smokes their reverse dependency closure' {
        $null=Invoke-QuietProperty -Name 'impact-ownership' -Seed $seed -Count 60 -Generator {param($random)
            $catalogue=& $newCatalogue $random
            $owners=[string[]](Get-QuietRandomSubset $random @($catalogue.Configuration.Companions.Keys) 0.4)
            $paths=@(foreach($owner in $owners){& $ownedPath $random $catalogue $owner})
            [pscustomobject]@{Catalogue=$catalogue;Owners=$owners;Paths=[string[]]$paths}
        } -Property {param($case)
            $result=& $impact $case.Catalogue $case.Paths
            $order=@($case.Catalogue.Configuration.Companions.Keys|Where-Object {$_ -cin $case.Owners})
            $smokes=@(& $expectedSmokes $case.Catalogue $case.Owners)
            if((@($result.FullSuites) -join ',') -cne ($order -join ',')){throw "full: $(@($result.FullSuites) -join ',') expected $($order -join ',')"}
            if((@($result.SmokeSuites) -join ',') -cne ($smokes -join ',')){throw "smoke: $(@($result.SmokeSuites) -join ',') expected $($smokes -join ',')"}
            if(@($result.SmokeSuites|Where-Object {$_ -cin @($result.FullSuites)}).Count){throw 'full and smoke overlap'}
            if($result.RunProducts -ne ($order.Count -gt 0)){throw 'RunProducts'}
            if($result.ConservativeFull -or $result.RunTooling -or $result.RunDistribution){throw 'unexpected flags'}
            $expectedSuite=if($order.Count -eq 1){$order[0]}elseif($order.Count){'Selected'}else{'None'}
            $result.Suite -ceq $expectedSuite
        }
    }

    It 'does not select a compiled project from a sibling directory sharing its prefix' {
        $catalogue=New-QuietCiCatalogue ([Random]::new(3))
        $owner=@($catalogue.Modules|Where-Object {$_.SolutionGroup -ceq 'Core' -and !$_.IsTest})[0]
        $script:project=[pscustomobject]@{Module=$owner.Name;Path=($owner.Path+'/Native/Core.csproj');Group='Core';References=@();Packages=@();Imports=@();EvaluationFailure=$null}
        Mock -ModuleName CiImpact Get-QuietCiProjectGraph { $script:project }
        $plan=& $impact $catalogue @($owner.Path+'/NativeExtra/file.cs')
        @($plan.BuildProjects).Count|Should -Be 0
    }

    It 'selects nothing for documentation-only changes' {
        $null=Invoke-QuietProperty -Name 'impact-docs' -Seed $seed -Count 40 -Generator {param($random)
            $catalogue=& $newCatalogue $random
            $paths=@(1..$random.Next(1,5)|ForEach-Object {
                Get-QuietRandomItem $random @(('docs/'+(New-QuietRandomString $random)+'.md'),('icons/'+(New-QuietRandomString $random)+'.svg'),((& $ownedPath $random $catalogue 'Core') -replace '\.[a-z0-9]+$','.md'))
            })
            [pscustomobject]@{Catalogue=$catalogue;Paths=[string[]]$paths}
        } -Property {param($case)
            $result=& $impact $case.Catalogue $case.Paths
            @($result.FullSuites).Count -eq 0 -and @($result.SmokeSuites).Count -eq 0 -and !$result.RunProducts -and !$result.RunTooling -and !$result.RunDistribution -and !$result.ConservativeFull -and $result.Suite -ceq 'None'
        }
    }

    It 'keeps Git ignore files in the diff without changing selection' {
        $null=Invoke-QuietProperty -Name 'impact-gitignore-neutral' -Seed $seed -Count 30 -Generator {param($random)
            $catalogue=& $newCatalogue $random
            $paths=Get-QuietRandomSubset $random @('scripts/lib/Example.psm1',(& $ownedPath $random $catalogue 'Core'),'docs/a.md') 0.5
            [pscustomobject]@{Catalogue=$catalogue;Paths=[string[]]@($paths);Nested=('src/'+(New-QuietRandomString $random)+'/.gitignore')}
        } -Property {param($case)
            $before=& $impact $case.Catalogue $case.Paths
            $paths=@($case.Paths)+@('.gitignore',$case.Nested)
            $after=& $impact $case.Catalogue $paths
            if (($after.ChangedPaths -join '|') -cne ($paths -join '|')) { throw 'ChangedPaths lost an input' }
            $before=ConvertTo-Json -InputObject ($before | Select-Object * -ExcludeProperty ChangedPaths) -Depth 6 -Compress
            $after=ConvertTo-Json -InputObject ($after | Select-Object * -ExcludeProperty ChangedPaths) -Depth 6 -Compress
            $after -ceq $before
        }
    }

    It 'never removes a selected or smoked suite when a path is added (monotonicity)' {
        $null=Invoke-QuietProperty -Name 'impact-monotonic' -Seed $seed -Count 50 -Generator {param($random)
            $catalogue=& $newCatalogue $random
            $pool=@(foreach($name in $catalogue.Configuration.Companions.Keys){& $ownedPath $random $catalogue $name})+@('docs/x.md','src/Tooling/test/FrenchExDev2.QuietCli.Tooling.Tests.PoSh/a.ps1','build/unknown.txt')
            $paths=[string[]](Get-QuietRandomSubset $random $pool 0.4)
            [pscustomobject]@{Catalogue=$catalogue;Paths=$paths;Extra=[string](Get-QuietRandomItem $random $pool)}
        } -Property {param($case)
            $before=& $impact $case.Catalogue $case.Paths
            $after=& $impact $case.Catalogue (@($case.Paths)+$case.Extra)
            $kept=@($before.FullSuites|Where-Object {$_ -cnotin @($after.FullSuites)})
            $covered=@(@($before.SmokeSuites)|Where-Object {$_ -cnotin (@($after.FullSuites)+@($after.SmokeSuites))})
            if($kept.Count -or $covered.Count){throw "dropped full=$($kept -join ',') smoke=$($covered -join ',')"}
            (!$before.RunTooling -or $after.RunTooling) -and (!$before.ConservativeFull -or $after.ConservativeFull)
        }
    }

    It 'does not depend on the order of the changed paths' {
        $null=Invoke-QuietProperty -Name 'impact-order' -Seed $seed -Count 50 -Generator {param($random)
            $catalogue=& $newCatalogue $random
            $paths=@(foreach($name in $catalogue.Configuration.Companions.Keys){if($random.Next(0,2)){& $ownedPath $random $catalogue $name}})+@('docs/a.md')
            [pscustomobject]@{Catalogue=$catalogue;Paths=[string[]]$paths;Shuffled=[string[]](Get-QuietShuffle $random $paths)}
        } -Property {param($case)
            $left=& $impact $case.Catalogue $case.Paths
            $right=& $impact $case.Catalogue $case.Shuffled
            foreach($name in 'Suite','RunProducts','RunTooling','RunDistribution','ConservativeFull'){if($left.$name -ne $right.$name){throw $name}}
            (@($left.FullSuites) -join ',') -ceq (@($right.FullSuites) -join ',') -and (@($left.SmokeSuites) -join ',') -ceq (@($right.SmokeSuites) -join ',')
        }
    }

    It 'runs every companion and tooling conservatively for an unknown shared input' {
        $null=Invoke-QuietProperty -Name 'impact-unknown' -Seed $seed -Count 30 -Generator {param($random)
            [pscustomobject]@{Catalogue=(& $newCatalogue $random);Path=('build/'+(New-QuietRandomString $random)+'.txt')}
        } -Property {param($case)
            $result=& $impact $case.Catalogue @($case.Path)
            $all=@($case.Catalogue.Configuration.Companions.Keys)
            if(!$result.ConservativeFull -or !$result.RunTooling -or !$result.RunProducts){throw 'flags'}
            if(@($result.SmokeSuites).Count){throw 'smokes'}
            if(@($result.Reasons|Where-Object Reason -CEQ 'SharedOrUnknownInput').Count -ne 1){throw 'reason'}
            (@($result.FullSuites) -join ',') -ceq ($all -join ',')
        }
    }

    It 'maps <Path> to its scope' -ForEach @(
        @{Path='src/Tooling/test/FrenchExDev2.QuietCli.Tooling.Tests.PoSh/a.ps1';Tooling=$true;Distribution=$false;Full='';Conservative=$false}
        @{Path='src/Distribution/test/FrenchExDev2.QuietCli.Distribution.Tests.PoSh/a.ps1';Tooling=$false;Distribution=$true;Full='';Conservative=$false}
        @{Path='.github/workflows/distribution-ci.yml';Tooling=$false;Distribution=$true;Full='';Conservative=$false}
        @{Path='.github/workflows/tooling-component-ci.yml';Tooling=$true;Distribution=$false;Full='';Conservative=$false}
        @{Path='.github/workflows/tooling-ci.yml';Tooling=$true;Distribution=$false;Full='';Conservative=$false}
        @{Path='.github/workflows/core-ci.yml';Tooling=$false;Distribution=$false;Full='Core';Conservative=$false}
        @{Path='.github/workflows/zzz-ci.yml';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
        @{Path='scripts/New-RunProfile.ps1';Script=$true;Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='scripts/Invoke-RunProfile.ps1';Script=$true;Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='scripts/lib/RunProfileStore.psm1';Script=$true;Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='FrenchExDev2.QuietCli.Tooling.Tests.PoSh/a.ps1';Tooling=$true;Distribution=$false;Full='';Conservative=$false}
        @{Path='FrenchExDev2.QuietCli.Tooling.Tests.PoShX/a.ps1';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
        @{Path='src/Tooling/test/FrenchExDev2.QuietCli.Tooling.Tests.PoShX/a.ps1';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
        @{Path='scripts/RunProfiles/my-profile.profile.psd1';Script=$true;Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='scripts/RunProfiles/My-Profile.profile.psd1';Script=$true;Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='scripts/lib/RunToolCache.psm1';Script=$true;Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='scripts/Build-Workspace.ps1';Script=$true;Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='scripts/nested/data/x.json';Script=$true;Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='.gitignore';Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='scripts/nested/.gitignore';Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='src/Core/.gitignore';Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='build/.gitignore.example';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
        @{Path='build/.GITIGNORE';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
        @{Path='Scripts/lib/x.psm1';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
        @{Path='scriptsx/a.ps1';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
        @{Path='src/Core/scripts/a.ps1';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
        @{Path='test/scripts/unit/lib/CiImpact.Tests.ps1';Script=$true;Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='test/scripts/coverage.inventory.json';Script=$true;Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='test/scripts/README.md';Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='Test/scripts/unit/x.Tests.ps1';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
        @{Path='test/scriptsx/a.ps1';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
        @{Path='src/Git/FrenchExDev2.QuietCli.Git.slnx';Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='Quietly.slnx';Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='README.MD';Tooling=$false;Distribution=$false;Full='';Conservative=$false}
        @{Path='build/x.txt';Tooling=$true;Distribution=$false;Full='Core,Git';Conservative=$true}
    ) {
        $catalogue=[pscustomobject]@{Configuration=[pscustomobject]@{Path='c';SHA256=('0'*64);Base='Core';
            Companions=[ordered]@{Core=[pscustomobject]@{Name='Core';requires=@();Image='base'};Git=[pscustomobject]@{Name='Git';requires=@('Core');Image='overlay'}}
            Suites=[ordered]@{Core=[pscustomobject]@{Name='Core';Group='Core';Requires=@('Core');CoreEvidence=$true;Qualification=@();TestsModule='T.Core'};Git=[pscustomobject]@{Name='Git';Group='Git';Requires=@('Git');CoreEvidence=$false;Qualification=@();TestsModule='T.Git'}}}
            Modules=@((New-QuietCiProject Tooling -Test),(New-QuietCiProject Distribution -Test))}
        $result=& $impact $catalogue @($Path)
        # A Tooling or Distribution owner flags its workflow only; it never records a companion reason.
        if(!$Conservative -and !$Full){@($result.Reasons).Count|Should -Be 0}
        $result.RunTooling|Should -Be $Tooling
        $result.RunDistribution|Should -Be $Distribution
        (@($result.FullSuites) -join ',')|Should -BeExactly $Full
        $result.ConservativeFull|Should -Be $Conservative
        # A repository script is handed to the script impact instead of selecting a workflow.
        (@($result.ScriptPaths) -join ',')|Should -BeExactly $(if($Script){$Path}else{''})
        ,$result.ScriptPaths|Should -BeOfType [string[]]
    }

    It 'smokes a dependent companion when only its dependency is selected through a workflow' {
        $catalogue=& $newCatalogue ([Random]::new(1))
        $catalogue.Configuration.Companions.Clear()
        $catalogue.Configuration.Companions.Add('Core',[pscustomobject]@{Name='Core';requires=@();Image='base'})
        $catalogue.Configuration.Companions.Add('Git',[pscustomobject]@{Name='Git';requires=@('Core');Image='overlay'})
        $catalogue.Configuration.Suites.Clear()
        $catalogue.Configuration.Suites.Add('Core',[pscustomobject]@{Name='Core';Group='Core';Requires=@('Core');CoreEvidence=$true;Qualification=@();TestsModule='T.Core'})
        $catalogue.Configuration.Suites.Add('Git',[pscustomobject]@{Name='Git';Group='Git';Requires=@('Git');CoreEvidence=$false;Qualification=@();TestsModule='T.Git'})
        $result=& $impact $catalogue @('.github/workflows/core-ci.yml')
        $result.Suite|Should -BeExactly 'Core'
        @($result.SmokeSuites)|Should -Be @('Git')
        @($result.Reasons|Where-Object Action -CEQ 'smoke').Companion|Should -Be @('Git')
    }

    It 'rejects malformed changed paths with CiImpactPathInvalid before reading the catalogue' -ForEach @(
        @{Path=''},@{Path='a\b.ps1'},@{Path='/abs.ps1'},@{Path='src/../x.ps1'},@{Path="a$([char]0)b"},@{Path='..'}
    ) {
        $script:catalogue=& $newCatalogue ([Random]::new(2))
        {Get-QuietCiImpact -WorkspaceRoot $TestDrive -ChangedPaths @('docs/a.md',$Path)}|Should -Throw -ExpectedMessage 'CiImpactPathInvalid'
        Should -Invoke -ModuleName CiImpact Read-QuietCiCompanions -Times 0 -Exactly
    }

    It 'fails only with CiImpactPathInvalid on fuzzed paths' {
        $null=Invoke-QuietProperty -Name 'impact-fuzz' -Seed $seed -Count 150 -Generator {param($random)
            [pscustomobject]@{Catalogue=(& $newCatalogue $random);Paths=[string[]]@(1..$random.Next(1,4)|ForEach-Object {New-QuietFuzzPath $random})}
        } -Property {param($case)
            try{$result=& $impact $case.Catalogue $case.Paths}catch{if($_.Exception.Message -cne 'CiImpactPathInvalid'){throw};return $true}
            $result.SchemaVersion -eq 2
        }
    }
}

Describe 'Get-QuietCiDispatchImpact' {
    BeforeAll {
        $dispatch={param($Catalogue,[string[]]$Suite)
            $script:catalogue=$Catalogue
            Get-QuietCiDispatchImpact -WorkspaceRoot $TestDrive -Suite $Suite
        }
        # Every manual plan qualifies the requested companions and tooling only, never reads a diff, and explains each one.
        $assertShape={param($Result,[string[]]$Full,[bool]$Tooling=$false)
            $Result.SchemaVersion|Should -Be 2
            $Result.RunProducts|Should -Be ($Full.Count -gt 0)
            $Result.RunTooling|Should -Be $Tooling
            $Result.RunDistribution|Should -BeFalse
            $Result.ConservativeFull|Should -BeFalse
            @($Result.ChangedPaths).Count|Should -Be 0
            @($Result.BuildProjects).Count|Should -Be 0
            @($Result.ScriptPaths).Count|Should -Be 0
            (@($Result.SelectedSuites) -join ',')|Should -BeExactly ($Full -join ',')
            $Result.Suite|Should -BeExactly $(if($Full.Count -eq 1){$Full[0]}elseif($Full.Count){'Selected'}else{'None'})
            $explained=@($Full)+@(if($Tooling){'Tooling'})
            (@($Result.Reasons|Where-Object Action -CEQ 'full'|ForEach-Object {$_.Input+'|'+$_.Companion+'|'+$_.Reason}) -join ',')|Should -BeExactly ((@($explained|ForEach-Object {'workflow_dispatch|'+$_+'|ManualDispatch'})) -join ',')
            (@($Result.Reasons|Where-Object Action -CEQ 'smoke'|ForEach-Object Companion|Sort-Object) -join ',')|Should -BeExactly (@($Result.SmokeSuites) -join ',')
        }
    }
    BeforeEach {
        Mock -ModuleName CiImpact Read-QuietCiCompanions { $script:catalogue.Configuration }
    }

    It 'qualifies every companion and the full tooling for all, in catalogue order, without smokes' {
        $null=Invoke-QuietProperty -Name 'dispatch-all' -Seed $seed -Count 30 -Generator {param($random)
            [pscustomobject]@{Catalogue=(& $newCatalogue $random);Spelling=(Get-QuietRandomItem $random @('all','ALL','All',' all '))}
        } -Property {param($case)
            $result=& $dispatch $case.Catalogue @($case.Spelling)
            & $assertShape $result ([string[]]@($case.Catalogue.Configuration.Companions.Keys)) $true
            @($result.SmokeSuites).Count -eq 0
        }
    }

    It 'runs only the full tooling for <Spelling>' -ForEach @(
        @{Spelling=@('Tooling')}
        @{Spelling=@('tooling')}
        @{Spelling=@(' TOOLING , tooling ')}
    ) {
        $catalogue=& $newCatalogue ([Random]::new(5))
        $result=& $dispatch $catalogue $Spelling
        & $assertShape $result ([string[]]@()) $true
        @($result.SmokeSuites).Count|Should -Be 0
    }

    It 'adds the full tooling to the named companions for <Spelling>' -ForEach @(
        @{Spelling=@('Core','Tooling')}
        @{Spelling=@('tooling,core')}
    ) {
        $catalogue=& $newCatalogue ([Random]::new(6))
        $catalogue.Configuration.Companions.Clear()
        $catalogue.Configuration.Companions.Add('Core',[pscustomobject]@{Name='Core';requires=@();Image='base'})
        $result=& $dispatch $catalogue $Spelling
        & $assertShape $result ([string[]]@('Core')) $true
    }

    It 'qualifies the named companions and smokes their unselected dependents' {
        $null=Invoke-QuietProperty -Name 'dispatch-named' -Seed $seed -Count 60 -Generator {param($random)
            $catalogue=& $newCatalogue $random
            $names=[string[]](Get-QuietRandomSubset $random @($catalogue.Configuration.Companions.Keys) 0.4)
            if(!$names.Count){$names=[string[]]@(Get-QuietRandomItem $random @($catalogue.Configuration.Companions.Keys))}
            # Each name is spelled in a random case, possibly repeated, as items or as one comma-separated value.
            $spelled=@(foreach($name in [string[]](Get-QuietShuffle $random ([string[]]$names+[string[]](Get-QuietRandomSubset $random $names 0.3)))){if($random.Next(0,2)){$name.ToLowerInvariant()}else{$name.ToUpperInvariant()}})
            $suite=if($random.Next(0,2)){[string[]]$spelled}else{[string[]]@(($spelled|ForEach-Object {' '+$_+' '}) -join ',')}
            [pscustomobject]@{Catalogue=$catalogue;Names=$names;Suite=$suite}
        } -Property {param($case)
            $result=& $dispatch $case.Catalogue $case.Suite
            $order=[string[]]@($case.Catalogue.Configuration.Companions.Keys|Where-Object {$_ -cin $case.Names})
            & $assertShape $result $order
            (@($result.SmokeSuites) -join ',') -ceq (@(& $expectedSmokes $case.Catalogue $order) -join ',')
        }
    }

    It 'rejects <Name> with <Error> before planning anything' -ForEach @(
        @{Name='no value';Suite=$null;Error='CiDispatchSuiteRequired'}
        @{Name='an empty list';Suite=@();Error='CiDispatchSuiteRequired'}
        @{Name='blank items';Suite=@('',' ',' , ');Error='CiDispatchSuiteRequired'}
        @{Name='an unknown companion';Suite=@('Core','Nope');Error='CiDispatchSuiteUnknown: Nope'}
        @{Name='a companion prefix';Suite=@('Cor');Error='CiDispatchSuiteUnknown: Cor'}
        @{Name='a wildcard';Suite=@('*');Error='CiDispatchSuiteUnknown: `*'}
    ) {
        $catalogue=& $newCatalogue ([Random]::new(3))
        $catalogue.Configuration.Companions.Clear()
        $catalogue.Configuration.Companions.Add('Core',[pscustomobject]@{Name='Core';requires=@();Image='base'})
        {& $dispatch $catalogue $Suite}|Should -Throw -ExpectedMessage $Error
    }

    It 'smokes Git when only Core is dispatched' {
        $catalogue=& $newCatalogue ([Random]::new(4))
        $catalogue.Configuration.Companions.Clear()
        $catalogue.Configuration.Companions.Add('Core',[pscustomobject]@{Name='Core';requires=@();Image='base'})
        $catalogue.Configuration.Companions.Add('Git',[pscustomobject]@{Name='Git';requires=@('Core');Image='overlay'})
        $catalogue.Configuration.Suites.Clear()
        $catalogue.Configuration.Suites.Add('Core',[pscustomobject]@{Name='Core';Group='Core';Requires=@('Core');CoreEvidence=$true;Qualification=@();TestsModule='T.Core'})
        $catalogue.Configuration.Suites.Add('Git',[pscustomobject]@{Name='Git';Group='Git';Requires=@('Git');CoreEvidence=$false;Qualification=@();TestsModule='T.Git'})
        $result=& $dispatch $catalogue @('core')
        & $assertShape $result ([string[]]@('Core'))
        @($result.SmokeSuites)|Should -Be @('Git')
        @($result.Reasons|Where-Object Action -CEQ 'smoke'|ForEach-Object {$_.Input+'|'+$_.Reason})|Should -Be @('DependencyGraph|ChangedRuntimeDependency')
    }
}

Describe 'Get-QuietCiImpact over the .NET project graph' {
    BeforeAll {
        $core='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh';$git='src/Git/src/FrenchExDev2.QuietCli.Git.PoSh'
        $tool='src/Tooling/test/FrenchExDev2.QuietCli.Tooling.Tests.PoSh'
        $package={param([string]$Name,[string]$Version='',[string]$Override='')[pscustomobject]@{Name=$Name;Condition='';Version=$Version;VersionOverride=$Override}}
        $node={param([string]$Path,[string]$Module,[string]$Group,[string[]]$Imports=@(),[object[]]$Packages=@(),[string[]]$References=@(),[string]$Failure)
            [pscustomobject]@{Path=$Path;Module=$Module;Group=$Group;IsTest=$false;Packages=$Packages;References=$References;Imports=$Imports;Frameworks=@('net10.0');RequiresEvaluation=$false;EvaluationFailure=$(if($Failure){$Failure}else{$null})}
        }
        $p=@{
            Native="$core/Net/Core.Native/Core.Native.csproj";Base="$core/Net/Core.Base/Core.Base.csproj";Nat="$core/Net/Core.Nat/Core.Nat.csproj"
            Over="$core/Net/Core.Over/Core.Over.csproj";Shadow="$core/Net/Core.Native/Shadow.csproj";Git="$git/Net/Git.Native/Git.Native.csproj";Tool="$tool/Net/Tool/Tool.csproj"
        }
        # Consumers precede their dependencies so a single directional scan cannot find the full closure.
        $graph=@(
            (& $node $p.Tool 'FrenchExDev2.QuietCli.Tooling.Tests.PoSh' 'Tooling' @('Directory.Build.props') @() @($p.Git))
            (& $node $p.Git 'FrenchExDev2.QuietCli.Git.PoSh' 'Git' @('Directory.Packages.props') @((& $package 'Other.Pkg')) @($p.Native))
            (& $node $p.Native 'FrenchExDev2.QuietCli.Core.PoSh' 'Core' @('Directory.Build.props','Directory.Packages.props') @((& $package 'Foo.Bar')) @($p.Base))
            (& $node $p.Base 'FrenchExDev2.QuietCli.Core.PoSh' 'Core')
            (& $node $p.Nat 'FrenchExDev2.QuietCli.Core.PoSh' 'Core' @('Directory.Packages.props') @((& $package 'Foo.Bar' '1.0.0')))
            (& $node $p.Over 'FrenchExDev2.QuietCli.Core.PoSh' 'Core' @('Directory.Packages.props') @((& $package 'Foo.Bar' '' '2.0.0')))
            # Same directory as Core.Native but owned by Git, and a central package user that does not import the file.
            (& $node $p.Shadow 'FrenchExDev2.QuietCli.Git.PoSh' 'Git' @() @((& $package 'Foo.Bar')))
        )
        $configuration=[pscustomobject]@{Path='c';SHA256=('0'*64);Base='Core'
            Companions=[ordered]@{Core=[pscustomobject]@{Name='Core';requires=@();Image='base'};Git=[pscustomobject]@{Name='Git';requires=@('Core');Image='overlay'}}
            Suites=[ordered]@{Core=[pscustomobject]@{Name='Core';Group='Core';Requires=@('Core');CoreEvidence=$true;Qualification=@();TestsModule='FrenchExDev2.QuietCli.Core.Tests.PoSh'};Git=[pscustomobject]@{Name='Git';Group='Git';Requires=@('Git');CoreEvidence=$false;Qualification=@();TestsModule='FrenchExDev2.QuietCli.Git.Tests.PoSh'}}}
        $modules=@((New-QuietCiProject Core),(New-QuietCiProject Core -Test),(New-QuietCiProject Git),(New-QuietCiProject Git -Test),(New-QuietCiProject Tooling -Test),(New-QuietCiProject Distribution -Test))
        $central={param([string]$Items,[string]$Properties='')
            '<Project><PropertyGroup><ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally>'+$Properties+'</PropertyGroup><ItemGroup>'+$Items+'</ItemGroup></Project>'
        }
        $baseline=& $central '<PackageVersion Include="Foo.Bar" Version="1.0.0" /><PackageVersion Include="Other.Pkg" Version="3.0.0" />'
        $smoke='DependencyGraph|<null>|<null>|Git|smoke|ChangedRuntimeDependency'
        $text={param($Reasons)@(foreach($reason in @($Reasons)){(@($reason.Input,$reason.Package,$reason.Project,$reason.Companion,$reason.Action,$reason.Reason)|ForEach-Object {if($null -eq $_){'<null>'}else{[string]$_}}) -join '|'})}
        $run={param([string[]]$Paths,[hashtable]$Previous=@{})Get-QuietCiImpact -WorkspaceRoot $TestDrive -ChangedPaths $Paths -PreviousFiles $Previous}
    }
    BeforeEach {
        $script:graph=$graph;$script:evaluated=$null;$script:ciConfiguration=$configuration;$script:ciModules=$modules
        Mock -ModuleName CiImpact Read-QuietCiCompanions { $script:ciConfiguration }
        Mock -ModuleName CiImpact Get-QuietWorkspaceProjects { $script:ciModules }
        Mock -ModuleName CiImpact Get-QuietCiProjectGraph { $script:evaluated=[bool]$Evaluate;$script:graph }
        $props=[IO.Path]::Combine($TestDrive,'Directory.Packages.props')
        if(Test-Path -LiteralPath $props){Remove-Item -LiteralPath $props}
    }

    It 'evaluates MSBuild for <Path> exactly when a C# or build file changes' -ForEach @(
        @{Path='docs/a.md';Evaluate=$false},@{Path='scripts/a.ps1';Evaluate=$false},@{Path='a/b.cs';Evaluate=$true}
        @{Path='a/b.csproj';Evaluate=$true},@{Path='Directory.Build.props';Evaluate=$true},@{Path='a/b.targets';Evaluate=$true}
    ) {
        $null=& $run @($Path)
        $script:evaluated|Should -Be $Evaluate
    }

    It 'runs every companion conservatively when a project cannot be evaluated' {
        $script:graph=@((& $node $p.Native 'FrenchExDev2.QuietCli.Core.PoSh' 'Core' -Failure 'MSB4025'))
        $result=& $run @('docs/a.md')
        (& $text $result.Reasons)|Should -Be @("MSBuildEvaluation|<null>|$($p.Native)|*|full|EvaluationUnavailable: MSB4025")
        (@($result.FullSuites) -join ',')|Should -BeExactly 'Core,Git'
        $result.ConservativeFull|Should -BeTrue
        $result.RunTooling|Should -BeFalse
    }

    It 'records one shared reason for an unknown input' {
        (& $text (& $run @('build/x.txt')).Reasons)|Should -Be @('build/x.txt|<null>|<null>|*|full|SharedOrUnknownInput')
    }

    It 'qualifies the owner without building it for a non C# file beside a project' {
        $path="$core/Net/Core.Native/run.ps1"
        $result=& $run @($path)
        (& $text $result.Reasons)|Should -Be @("$path|<null>|$core|Core|full|SourceChanged",$smoke)
        @($result.BuildProjects).Count|Should -Be 0
        (@($result.ChangedPaths) -join ',')|Should -BeExactly $path
        $result.ConservativeFull|Should -BeFalse
    }

    It 'builds the owning project of <Leaf>, its reverse and forward closures, without selecting dependents' -ForEach @(
        @{Leaf='Interop.cs'},@{Leaf='Nested/Interop.cs'},@{Leaf='Core.Native.csproj'}
    ) {
        $path="$core/Net/Core.Native/$Leaf"
        $result=& $run @($path)
        (& $text $result.Reasons)|Should -Be @("$path|<null>|$core|Core|full|SourceChanged","$path||$($p.Native)|Core|build|SourceChanged",$smoke)
        @($result.BuildProjects)|Should -Be @(@($p.Native,$p.Base,$p.Git,$p.Tool)|Sort-Object)
        (@($result.FullSuites) -join ',')|Should -BeExactly 'Core'
        (@($result.SmokeSuites) -join ',')|Should -BeExactly 'Git'
    }

    It 'follows the forward reference closure transitively' {
        $result=& $run @("$git/Net/Git.Native/Repository.cs")
        @($result.BuildProjects)|Should -Be @(@($p.Native,$p.Base,$p.Git,$p.Tool)|Sort-Object)
        (@($result.FullSuites) -join ',')|Should -BeExactly 'Git'
        @($result.SmokeSuites).Count|Should -Be 0
    }

    It 'visits cyclic prerequisites once without selecting their unrelated consumers' {
        $script:graph=@(
            (& $node $p.Shadow 'FrenchExDev2.QuietCli.Git.PoSh' 'Git' -References @($p.Base))
            (& $node $p.Git 'FrenchExDev2.QuietCli.Git.PoSh' 'Git' -References @($p.Native))
            (& $node $p.Native 'FrenchExDev2.QuietCli.Core.PoSh' 'Core' -References @($p.Base))
            (& $node $p.Base 'FrenchExDev2.QuietCli.Core.PoSh' 'Core' -References @($p.Nat))
            (& $node $p.Nat 'FrenchExDev2.QuietCli.Core.PoSh' 'Core' -References @($p.Base))
        )

        $result=& $run @("$core/Net/Core.Native/Interop.cs")
        @($result.BuildProjects)|Should -Be @(@($p.Native,$p.Base,$p.Nat,$p.Git)|Sort-Object)
        @($result.FullSuites)|Should -Be @('Core')
        @($result.SmokeSuites)|Should -Be @('Git')
    }

    It 'owns <Path> by module name only up to a separator' -ForEach @(
        @{Path='FrenchExDev2.QuietCli.Core.PoSh/a.ps1';Full='Core';Conservative=$false}
        @{Path='FrenchExDev2.QuietCli.Core.PoShX/a.ps1';Full='Core,Git';Conservative=$true}
        @{Path='src/Core/src/FrenchExDev2.QuietCli.Core.PoShX/a.ps1';Full='Core,Git';Conservative=$true}
    ) {
        $result=& $run @($Path)
        (@($result.FullSuites) -join ',')|Should -BeExactly $Full
        $result.ConservativeFull|Should -Be $Conservative
    }

    It 'builds the importers of an inherited build input <Path>' -ForEach @(
        @{Path='Directory.Build.props';Affected=@('Tool','Native')}
        @{Path='global.json';Affected=@('Tool','Git','Native','Base','Nat','Over','Shadow')}
        @{Path='NuGet.Config';Affected=@()}
    ) {
        $result=& $run @($Path)
        $expected=@(foreach($key in $Affected){$project=$graph|Where-Object Path -CEQ $p[$key];"$Path||$($project.Path)|$($project.Group)|build|InheritedBuildInput"})
        ((& $text @($result.Reasons|Where-Object Action -CEQ 'build')) -join "`n")|Should -BeExactly ($expected -join "`n")
        $result.ConservativeFull|Should -BeFalse
        if(!$Affected.Count){@($result.BuildProjects).Count|Should -Be 0}
    }

    It 'selects the owner suites of the props importers' {
        $result=& $run @('Directory.Build.props')
        # Tool (Tooling) and Core.Native import it; Git.Native is only rebuilt as a reverse dependency.
        (@($result.FullSuites) -join ',')|Should -BeExactly 'Core'
        @($result.BuildProjects)|Should -Be @(@($p.Native,$p.Base,$p.Git,$p.Tool)|Sort-Object)
        $result.RunTooling|Should -BeFalse
    }

    Context 'Directory.Packages.props' {
        BeforeAll {
            $write={param([string]$Text)[IO.File]::WriteAllText([IO.Path]::Combine($TestDrive,'Directory.Packages.props'),$Text,[Text.UTF8Encoding]::new($false))}
            $expectBuilds={param([string[]]$Keys,[string]$Reason,[string]$Package)@(foreach($key in $Keys){$project=$graph|Where-Object Path -CEQ $p[$key];"Directory.Packages.props|$Package|$($project.Path)|$($project.Group)|build|$Reason"})}
        }

        It 'builds only central consumers of a bumped package without a local version' {
            & $write (& $central '<PackageVersion Include="Foo.Bar" Version="1.1.0" /><PackageVersion Include="Other.Pkg" Version="3.0.0" />')
            $result=& $run @('Directory.Packages.props') @{'Directory.Packages.props'=$baseline}
            (& $text @($result.Reasons|Where-Object Action -CEQ 'build'))|Should -Be (& $expectBuilds @('Native') 'CentralPackageConsumer' 'foo.bar')
            (@($result.FullSuites) -join ',')|Should -BeExactly 'Core'
            $result.ConservativeFull|Should -BeFalse
        }

        It 'joins every bumped package in the build reason' {
            & $write (& $central '<PackageVersion Include="Foo.Bar" Version="1.1.0" /><PackageVersion Include="Other.Pkg" Version="3.1.0" />')
            $result=& $run @('Directory.Packages.props') @{'Directory.Packages.props'=$baseline}
            (& $text @($result.Reasons|Where-Object Action -CEQ 'build'))|Should -Be (& $expectBuilds @('Git','Native') 'CentralPackageConsumer' 'foo.bar,other.pkg')
            (@($result.FullSuites) -join ',')|Should -BeExactly 'Core,Git'
        }

        It 'builds every importer conservatively when transitive pinning is enabled' {
            $pinning='<CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>'
            & $write (& $central '<PackageVersion Include="Foo.Bar" Version="1.1.0" /><PackageVersion Include="Other.Pkg" Version="3.0.0" />' $pinning)
            $before=& $central '<PackageVersion Include="Foo.Bar" Version="1.0.0" /><PackageVersion Include="Other.Pkg" Version="3.0.0" />' $pinning
            $result=& $run @('Directory.Packages.props') @{'Directory.Packages.props'=$before}
            (& $text @($result.Reasons|Where-Object Action -CEQ 'build'))|Should -Be (& $expectBuilds @('Git','Native','Nat','Over') 'TransitivePinningRequiresResolvedConsumerGraph' 'foo.bar')
            $result.ConservativeFull|Should -BeTrue
        }

        It 'treats a disabled transitive pinning <Value> as a plain central bump' -ForEach @(@{Value='false'},@{Value=' False '}) {
            $pinning="<CentralPackageTransitivePinningEnabled>$Value</CentralPackageTransitivePinningEnabled>"
            & $write (& $central '<PackageVersion Include="Foo.Bar" Version="1.1.0" /><PackageVersion Include="Other.Pkg" Version="3.0.0" />' $pinning)
            $before=& $central '<PackageVersion Include="Foo.Bar" Version="1.0.0" /><PackageVersion Include="Other.Pkg" Version="3.0.0" />' $pinning
            $result=& $run @('Directory.Packages.props') @{'Directory.Packages.props'=$before}
            (& $text @($result.Reasons|Where-Object Action -CEQ 'build'))|Should -Be (& $expectBuilds @('Native') 'CentralPackageConsumer' 'foo.bar')
            $result.ConservativeFull|Should -BeFalse
        }

        It 'builds nothing when pinning is enabled but no package changes' {
            $pinning='<CentralPackageTransitivePinningEnabled>true</CentralPackageTransitivePinningEnabled>'
            & $write (& $central '<PackageVersion Include="Other.Pkg" Version="3.0.0" /><PackageVersion Include="Foo.Bar" Version="1.0.0" />' $pinning)
            $before=& $central '<PackageVersion Include="Foo.Bar" Version="1.0.0" /><PackageVersion Include="Other.Pkg" Version="3.0.0" />' $pinning
            $result=& $run @('Directory.Packages.props') @{'Directory.Packages.props'=$before}
            @($result.Reasons).Count|Should -Be 0
            @($result.BuildProjects).Count|Should -Be 0
            $result.ConservativeFull|Should -BeFalse
            $result.RunProducts|Should -BeFalse
        }

        It 'builds every importer when the central restore policy changes' {
            & $write (& $central '<PackageVersion Include="Foo.Bar" Version="1.0.0" /><PackageVersion Include="Other.Pkg" Version="3.0.0" />' '<CentralPackageVersionOverrideEnabled>false</CentralPackageVersionOverrideEnabled>')
            $result=& $run @('Directory.Packages.props') @{'Directory.Packages.props'=$baseline}
            (& $text @($result.Reasons|Where-Object Action -CEQ 'build'))|Should -Be (& $expectBuilds @('Git','Native','Nat','Over') 'CentralRestorePolicyChanged' '')
            $result.ConservativeFull|Should -BeFalse
        }

        It 'treats a deleted central file as a restore policy change of every removed package' {
            $result=& $run @('Directory.Packages.props') @{'Directory.Packages.props'=$baseline}
            (& $text @($result.Reasons|Where-Object Action -CEQ 'build'))|Should -Be (& $expectBuilds @('Git','Native','Nat','Over') 'CentralRestorePolicyChanged' 'foo.bar,other.pkg')
            $result.ConservativeFull|Should -BeFalse
        }

        It 'builds every importer conservatively without a baseline' {
            & $write $baseline
            $result=& $run @('Directory.Packages.props')
            (& $text @($result.Reasons|Where-Object Action -CEQ 'build'))|Should -Be (& $expectBuilds @('Git','Native','Nat','Over') 'BaselineUnavailable' '')
            $result.ConservativeFull|Should -BeTrue
        }
    }
}

Describe 'Test-QuietDevelopReceipt' {
    BeforeAll {
        $tree='a'*40
        $newReceipt={param([bool]$Performance,[bool]$Tooling,[bool]$Mutation)
            [pscustomobject]@{Tree=$tree;Ready=$true;RunId='17';RunAttempt='2';Windows='success';Linux='success'
                PerformanceRequired=$Performance;Performance=$(if($Performance){'success'}else{'skipped'})
                ToolingRequired=$Tooling;Tooling=$(if($Tooling){'success'}else{'skipped'});ToolingMutation=$(if($Tooling){'success'}else{'skipped'})
                MutationRequired=$Mutation;Mutation=$(if($Mutation){'success'}else{'skipped'})}
        }
    }

    It 'accepts every consistent receipt for the exact tree and attempt' -ForEach @(
        foreach($p in $false,$true){foreach($t in $false,$true){foreach($m in $false,$true){@{P=$p;T=$t;M=$m}}}}
    ) {
        Test-QuietDevelopReceipt -Receipt (& $newReceipt $P $T $M) -Tree $tree -RunId '17' -RunAttempt '2'|Should -BeTrue
    }

    It 'rejects a receipt when any single field is altered' {
        $null=Invoke-QuietProperty -Name 'receipt-single-change' -Seed $seed -Count 200 -Generator {param($random)
            $flags=[bool[]]@(($random.Next(0,2) -eq 1),($random.Next(0,2) -eq 1),($random.Next(0,2) -eq 1))
            $field=Get-QuietRandomItem $random @('Tree','Ready','RunId','RunAttempt','Windows','Linux','PerformanceRequired','Performance','ToolingRequired','Tooling','ToolingMutation','MutationRequired','Mutation')
            [pscustomobject]@{Flags=$flags;Field=$field;Pick=$random.Next(0,1000)}
        } -Property {param($case)
            $receipt=& $newReceipt $case.Flags[0] $case.Flags[1] $case.Flags[2]
            $value=$receipt.($case.Field)
            $receipt.($case.Field)=switch($case.Field){
                'Tree'{'b'*40}
                {$_ -in 'Ready'}{Get-QuietRandomItem ([Random]::new($case.Pick)) @($false,'true',1,$null)}
                {$_ -in 'PerformanceRequired','ToolingRequired','MutationRequired'}{Get-QuietRandomItem ([Random]::new($case.Pick)) @((!$value),([string]$value),$null)}
                {$_ -in 'RunId','RunAttempt'}{Get-QuietRandomItem ([Random]::new($case.Pick)) @('18','0',' 17',$null)}
                default{Get-QuietRandomItem ([Random]::new($case.Pick)) @($(if($value -ceq 'success'){'skipped'}else{'success'}),'failure','Success',$null)}
            }
            $verdict=Test-QuietDevelopReceipt -Receipt $receipt -Tree $tree -RunId '17' -RunAttempt '2'
            $verdict -is [bool] -and !$verdict
        }
    }

    It 'rejects a malformed expected tree' -ForEach @(@{Tree='A'*40},@{Tree='a'*39},@{Tree=''},@{Tree=('a'*40)+"`n"}) {
        $receipt=& $newReceipt $false $false $false;$receipt.Tree=$Tree
        $verdict=Test-QuietDevelopReceipt -Receipt $receipt -Tree $Tree -RunId '17' -RunAttempt '2'
        $verdict|Should -BeOfType [bool]
        $verdict|Should -BeFalse
    }
}
