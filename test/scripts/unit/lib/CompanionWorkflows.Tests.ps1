#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Generators.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','Property.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','CiFixtures.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name CompanionWorkflows
    $null=Import-QuietTestLibrary -Name Resources
    $null=Ensure-QuietResource -WorkspaceRoot (Get-QuietTestWorkspaceRoot) -RelativePath resources/yaml/YamlDotNet.dll -AssemblyType YamlDotNet.Serialization.DeserializerBuilder
    $seed=Get-QuietTestSeed
    # Profiles only test for build/companions.yml; its content comes from the mocked reader.
    $root=[IO.Path]::Combine($TestDrive,'workspace')
    $null=New-QuietTestFile ([IO.Path]::Combine($root,'build','companions.yml')) 'mocked'
    [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($root,'.github','workflows'))
    $parseYaml={param([string]$Text)[YamlDotNet.Serialization.DeserializerBuilder]::new().WithDuplicateKeyChecking().Build().Deserialize($Text)}
    $use={param($Catalogue)$script:catalogue=$Catalogue}
}

Describe 'CompanionWorkflows' {
    BeforeEach {
        Mock -ModuleName CompanionWorkflows Read-QuietCiCompanions { $script:catalogue.Configuration }
        Mock -ModuleName CompanionWorkflows Get-QuietWorkspaceProjects { $script:catalogue.Modules }
    }

    Context 'Get-QuietCompanionProfiles' {
        It 'takes both parent directories from the catalogue declaration' {
            & $use (New-QuietCiCatalogue ([Random]::new(3)))
            $script:catalogue.Configuration.Companions['Core']|Add-Member -Force -NotePropertyMembers @{SourcePath='src/Alternate/src/Product';TestPath='src/Alternate/test/Product.Tests'}
            $definition=Get-QuietCompanionProfiles -WorkspaceRoot $root|Where-Object Suite -CEQ Core
            $definition.SourcePath|Should -BeExactly 'src/Alternate/src'
            $definition.TestPath|Should -BeExactly 'src/Alternate/test'
        }
        It 'derives one profile per solution group with its engine, paths and performance policy' {
            $null=Invoke-QuietProperty -Name 'workflow-profiles' -Seed $seed -Count 40 -Generator {param($random)
                $catalogue=New-QuietCiCatalogue $random
                # Some companions ship tests only.
                $drop=[object[]](Get-QuietRandomSubset $random @($catalogue.Configuration.Companions.Keys|Where-Object {$_ -cne 'Core'}) 0.3)
                $catalogue.Modules=@($catalogue.Modules|Where-Object {!($_.SolutionGroup -cin $drop -and !$_.IsTest)})
                [pscustomobject]@{Catalogue=$catalogue;Dropped=[string[]]$drop}
            } -Property {param($case)
                & $use $case.Catalogue
                $profiles=@(Get-QuietCompanionProfiles -WorkspaceRoot $root)
                $groups=@($case.Catalogue.Modules.SolutionGroup|Sort-Object -Unique)
                if((@($profiles.Suite) -join ',') -cne ($groups -join ',')){throw "groups $(@($profiles.Suite) -join ',')"}
                foreach($companionProfile in $profiles){
                    $product=$case.Catalogue.Configuration.Companions.Contains($companionProfile.Suite)
                    $file=if($product){'ci.yml'}elseif($companionProfile.Suite -ceq 'Tooling'){'tooling-component-ci.yml'}else{'distribution-ci.yml'}
                    if($companionProfile.Workflow -cne ".github/workflows/$file"){throw "workflow $($companionProfile.Suite)"}
                    if($companionProfile.Engine -cne $(if($product){'ci.yml'}else{'workspace-component-ci.yml'})){throw "engine $($companionProfile.Suite)"}
                    if($companionProfile.SolutionPath -cne "src/$($companionProfile.Suite)/$($companionProfile.Suite).slnx" -or $companionProfile.TestPath -cne "src/$($companionProfile.Suite)/test" -or $companionProfile.Root -cne "src/$($companionProfile.Suite)"){throw "paths $($companionProfile.Suite)"}
                    $members=@($case.Catalogue.Modules|Where-Object SolutionGroup -CEQ $companionProfile.Suite)
                    $sources=@($members|Where-Object {!$_.IsTest}|ForEach-Object Path);$tests=@($members|Where-Object IsTest|ForEach-Object Path)
                    if((@($companionProfile.Sources) -join ',') -cne (@($sources) -join ',') -or (@($companionProfile.Tests) -join ',') -cne (@($tests) -join ',')){throw "members $($companionProfile.Suite)"}
                    if($companionProfile.SourcePath -cne $(if(@($sources).Count){"src/$($companionProfile.Suite)/src"}else{''})){throw "source $($companionProfile.Suite)"}
                    if($companionProfile.CollectPerformance -ne ($companionProfile.Suite -ceq 'Core')){throw "performance $($companionProfile.Suite)"}
                }
                $true
            }
        }

        It 'rejects a solution group that is neither a companion nor a component' {
            & $use (New-QuietCiCatalogue ([Random]::new(3)))
            $script:catalogue.Modules+=New-QuietCiProject Stray -Test
            {Get-QuietCompanionProfiles -WorkspaceRoot $root}|Should -Throw -ExpectedMessage 'CompanionCiProfileMissing: Stray'
        }

        It 'requires the catalogue once grouped projects exist and ignores legacy fixtures without one' {
            $bare=[IO.Path]::Combine($TestDrive,'bare');[void][IO.Directory]::CreateDirectory($bare)
            & $use (New-QuietCiCatalogue ([Random]::new(4)))
            {Get-QuietCompanionProfiles -WorkspaceRoot $bare}|Should -Throw -ExpectedMessage 'CompanionCiCatalogueRequired'
            $script:catalogue.Modules=@([pscustomobject]@{Name='FrenchExDev2.QuietCli.Legacy.PoSh';Path='FrenchExDev2.QuietCli.Legacy.PoSh';SolutionGroup='Legacy';IsTest=$false})
            @(Get-QuietCompanionProfiles -WorkspaceRoot $bare).Count|Should -Be 0
            Should -Invoke -ModuleName CompanionWorkflows Read-QuietCiCompanions -Times 0 -Exactly
        }
    }

    Context 'Get-QuietCompanionWorkflowDefinitions' {
        It 'renders parseable workflows that call the profile engine with the profile paths' {
            $null=Invoke-QuietProperty -Name 'workflow-render' -Seed $seed -Count 25 -Generator {param($random)New-QuietCiCatalogue $random} -Property {param($catalogue)
                & $use $catalogue
                $entries=@(Get-QuietCompanionWorkflowDefinitions -WorkspaceRoot $root)
                if(($entries.Profile.Suite -join ',') -cne 'Distribution,Tooling'){throw 'component entries'}
                foreach($entry in $entries){
                    $companionProfile=$entry.Profile
                    if($entry.Path -cne $companionProfile.Workflow){throw 'path'}
                    if($entry.Content.Contains('%') -or !$entry.Content.EndsWith("`n") -or $entry.Content.EndsWith("`n`n") -or $entry.Content.Contains("`r")){throw "layout $($companionProfile.Suite)"}
                    $document=& $parseYaml $entry.Content
                    $with=$document['jobs']['qualify']['with']
                    if($document['name'] -cne "QuietCli $($companionProfile.Suite)" -or $document['jobs']['qualify']['uses'] -cne "./.github/workflows/$($companionProfile.Engine)"){throw "call $($companionProfile.Suite)"}
                    if($with['suite'] -cne $companionProfile.Suite -or $with['solution_path'] -cne $companionProfile.SolutionPath -or $with['source_path'] -cne $companionProfile.SourcePath -or $with['test_path'] -cne $companionProfile.TestPath){throw "with $($companionProfile.Suite)"}
                    if($with['qualification_mode'] -cne '${{ inputs.qualification_mode || ''full'' }}'){throw 'mode'}
                    $product=$companionProfile.Engine -ceq 'ci.yml'
                    if(($document['permissions'].ContainsKey('packages')) -ne $product){throw "packages $($companionProfile.Suite)"}
                    if($product){
                        if($document['permissions']['packages'] -cne 'write' -or $with['run_tooling'] -cne 'false' -or $with['collect_performance'] -cne $companionProfile.CollectPerformance.ToString().ToLowerInvariant()){throw "product $($companionProfile.Suite)"}
                    }elseif($with.ContainsKey('run_tooling') -or $with.ContainsKey('collect_performance')){throw "component $($companionProfile.Suite)"}
                    if(@($document['on'].Keys) -join ',' -cne 'workflow_call,workflow_dispatch'){throw 'triggers'}
                }
                $true
            }
        }
    }

    Context 'Sync-QuietCompanionWorkflows' {
        BeforeEach {
            & $use (New-QuietCiCatalogue ([Random]::new(5)))
            Get-ChildItem -LiteralPath ([IO.Path]::Combine($root,'.github','workflows')) -File|Remove-Item -Force
            # The image rule has its own tests in CiCompanions.Tests.ps1; here it only gates the writes.
            Mock -ModuleName CompanionWorkflows Assert-QuietCiCompanionImages {}
        }

        It 'checks the companion image rule on the read configuration before writing anything' {
            Mock -ModuleName CompanionWorkflows Assert-QuietCiCompanionImages { throw 'CiCompanionImageMustBeOverlay: Fixture' }
            {Sync-QuietCompanionWorkflows -WorkspaceRoot $root -Apply -Confirm:$false}|Should -Throw -ExpectedMessage 'CiCompanionImageMustBeOverlay: Fixture'
            @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($root,'.github','workflows')) -File).Count|Should -Be 0
            Should -Invoke -ModuleName CompanionWorkflows Assert-QuietCiCompanionImages -Times 1 -Exactly -ParameterFilter {$WorkspaceRoot -ceq $root -and [object]::ReferenceEquals($Configuration,$script:catalogue.Configuration)}
        }

        It 'requires declared <Property> to exist before generating a workflow' -ForEach @(
            @{Property='SourcePath';Relative='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh'},
            @{Property='TestPath';Relative='src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh'}
        ) {
            $script:catalogue.Configuration.Companions['Core']|Add-Member -NotePropertyName $Property -NotePropertyValue $Relative -Force
            {Sync-QuietCompanionWorkflows -WorkspaceRoot $root -Apply -Confirm:$false}|
                Should -Throw -ExpectedMessage ('CiCompanionPathMissing: '+$Relative)
            Should -Invoke -ModuleName CompanionWorkflows Assert-QuietCiCompanionImages -Times 0 -Exactly
            $null=New-Item -Path ([IO.Path]::Combine($root,$Relative)) -ItemType Directory
            {Sync-QuietCompanionWorkflows -WorkspaceRoot $root -Apply -Confirm:$false}|Should -Not -Throw
        }

        It 'skips the image rule without a catalogue, then still requires one for grouped projects' {
            $bare=[IO.Path]::Combine($TestDrive,'sync-bare');[void][IO.Directory]::CreateDirectory([IO.Path]::Combine($bare,'.github','workflows'))
            $script:catalogue.Modules=@([pscustomobject]@{Name='FrenchExDev2.QuietCli.Legacy.PoSh';Path='FrenchExDev2.QuietCli.Legacy.PoSh';SolutionGroup='Legacy';IsTest=$false})
            @(Sync-QuietCompanionWorkflows -WorkspaceRoot $bare).Count|Should -Be 0
            @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($bare,'.github','workflows')) -File).Count|Should -Be 0
            & $use (New-QuietCiCatalogue ([Random]::new(5)))
            {Sync-QuietCompanionWorkflows -WorkspaceRoot $bare}|Should -Throw -ExpectedMessage 'CompanionCiCatalogueRequired'
            Should -Invoke -ModuleName CompanionWorkflows Assert-QuietCiCompanionImages -Times 0 -Exactly
            Should -Invoke -ModuleName CompanionWorkflows Read-QuietCiCompanions -Times 0 -Exactly
        }

        It 'reports drift without writing, then applies, and is idempotent' {
            $first=@(Get-QuietCompanionWorkflowDefinitions -WorkspaceRoot $root)[0]
            {Sync-QuietCompanionWorkflows -WorkspaceRoot $root}|Should -Throw -ExpectedMessage ('CompanionWorkflowDrift: '+$first.Path)
            @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($root,'.github','workflows')) -File).Count|Should -Be 0
            Sync-QuietCompanionWorkflows -WorkspaceRoot $root -Apply -Confirm:$false
            foreach($entry in Get-QuietCompanionWorkflowDefinitions -WorkspaceRoot $root){
                $bytes=[IO.File]::ReadAllBytes([IO.Path]::Combine($root,$entry.Path))
                ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB)|Should -BeFalse -Because 'workflows are written without a BOM'
                [Text.Encoding]::UTF8.GetString($bytes)|Should -BeExactly $entry.Content
            }
            {Sync-QuietCompanionWorkflows -WorkspaceRoot $root}|Should -Not -Throw
        }

        It 'reports a hand-edited workflow as drift and leaves untouched files alone' {
            Sync-QuietCompanionWorkflows -WorkspaceRoot $root -Apply -Confirm:$false
            $entries=@(Get-QuietCompanionWorkflowDefinitions -WorkspaceRoot $root)
            $edited=[IO.Path]::Combine($root,$entries[-1].Path)
            [IO.File]::WriteAllText($edited,$entries[-1].Content+'# edit'+"`n")
            $stamp=[datetime]::new(2001,1,1,0,0,0,[DateTimeKind]::Utc)
            foreach($entry in $entries|Select-Object -SkipLast 1){[IO.File]::SetLastWriteTimeUtc([IO.Path]::Combine($root,$entry.Path),$stamp)}
            {Sync-QuietCompanionWorkflows -WorkspaceRoot $root}|Should -Throw -ExpectedMessage ('CompanionWorkflowDrift: '+$entries[-1].Path)
            Sync-QuietCompanionWorkflows -WorkspaceRoot $root -Apply -Confirm:$false
            [IO.File]::ReadAllText($edited)|Should -BeExactly $entries[-1].Content
            foreach($entry in $entries|Select-Object -SkipLast 1){[IO.File]::GetLastWriteTimeUtc([IO.Path]::Combine($root,$entry.Path))|Should -Be $stamp}
        }

        It 'writes nothing under -WhatIf' {
            Sync-QuietCompanionWorkflows -WorkspaceRoot $root -Apply -WhatIf
            @(Get-ChildItem -LiteralPath ([IO.Path]::Combine($root,'.github','workflows')) -File).Count|Should -Be 0
        }
    }

    Context 'Assert-QuietCompanionProfile' {
        BeforeEach { & $use (New-QuietCiCatalogue ([Random]::new(6))) }

        It 'accepts All without paths and rejects All with <Name>' -ForEach @(
            @{Name='a solution';Arguments=@{SolutionPath='x.slnx'}},@{Name='a source path';Arguments=@{SourcePath='src'}},@{Name='a test path';Arguments=@{TestPath='test'}}
        ) {
            {Assert-QuietCompanionProfile -WorkspaceRoot $root -Suite All}|Should -Not -Throw
            {Assert-QuietCompanionProfile -WorkspaceRoot $root -Suite All @Arguments}|Should -Throw -ExpectedMessage 'AllDoesNotHaveCompanionPaths'
        }

        It 'accepts the discovered paths, omitted paths, and rejects any other value' {
            foreach($companionProfile in Get-QuietCompanionProfiles -WorkspaceRoot $root){
                {Assert-QuietCompanionProfile -WorkspaceRoot $root -Suite $companionProfile.Suite}|Should -Not -Throw
                {Assert-QuietCompanionProfile -WorkspaceRoot $root -Suite $companionProfile.Suite -SolutionPath $companionProfile.SolutionPath -SourcePath $companionProfile.SourcePath -TestPath $companionProfile.TestPath}|Should -Not -Throw
                foreach($name in 'SolutionPath','SourcePath','TestPath'){
                    $arguments=@{$name=($companionProfile.$name+'x').ToUpperInvariant()}
                    {Assert-QuietCompanionProfile -WorkspaceRoot $root -Suite $companionProfile.Suite @arguments}|Should -Throw -ExpectedMessage ('CompanionProfilePathMismatch: '+$name)
                }
            }
        }

        It 'rejects an unknown or differently cased suite' -ForEach @(@{Suite='Nope'},@{Suite='core'}) {
            {Assert-QuietCompanionProfile -WorkspaceRoot $root -Suite $Suite}|Should -Throw -ExpectedMessage ('CompanionProfileUnknown: '+$Suite)
        }
    }

    It 'checks, previews and refreshes the current YAML catalogue checklist using its exact path' {
        $currentRoot=[IO.Path]::Combine($TestDrive,'current-checklist')
        $cataloguePath=New-QuietTestFile ([IO.Path]::Combine($currentRoot,'build','companions.yaml')) 'fixture'
        & $use @{Modules=@();Configuration=@{Path=$cataloguePath;Companions=[ordered]@{Box2=@{Name='Box2';Mutation=$true}}}}
        Mock -ModuleName CompanionWorkflows Assert-QuietCiCompanionImages {}
        $path=[IO.Path]::Combine($currentRoot,'.github','pull_request_template.md')
        $expected=("<!-- quietcli-ci:begin -->`n- [ ] Scripts <!-- ci:script-mutation -->`n- [ ] Run Box2 mutation testing <!-- ci:run-profile-mutation-box2 -->`n- [ ] Profile the Box2 PowerShell tests <!-- ci:profiling-box2 -->`n- [ ] Serial <!-- ci:mutation-serial -->`n- [ ] R2R <!-- ci:readytorun -->`n- [ ] Preview <!-- ci:preview -->`n<!-- quietcli-ci:end -->`n")
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($path))
        [IO.File]::WriteAllText($path,($expected.Replace("`n","`r`n")),[Text.UTF8Encoding]::new($false))
        {Sync-QuietCompanionWorkflows -WorkspaceRoot $currentRoot}|Should -Not -Throw
        $stale=$expected.Replace('Box2','Old').Replace('box2','old')
        [IO.File]::WriteAllText($path,$stale,[Text.Encoding]::UTF8)
        {Sync-QuietCompanionWorkflows -WorkspaceRoot $currentRoot}|Should -Throw '*CompanionPullRequestTemplateDrift*'
        Sync-QuietCompanionWorkflows -WorkspaceRoot $currentRoot -Apply -WhatIf
        [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)|Should -BeExactly $stale
        Sync-QuietCompanionWorkflows -WorkspaceRoot $currentRoot -Apply -Confirm:$false
        [IO.File]::ReadAllText($path,[Text.Encoding]::UTF8)|Should -BeExactly $expected
        [IO.File]::ReadAllBytes($path)[0]|Should -Be ([byte][char]'<')
    }
}
