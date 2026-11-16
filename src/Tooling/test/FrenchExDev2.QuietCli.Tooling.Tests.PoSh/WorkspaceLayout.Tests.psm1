
function New-QuietLayoutFixture {
    <#
    .SYNOPSIS
    Creates a Git-free catalogue of 120 independently selectable companions.
    .PARAMETER WorkspaceRoot
    Checkout supplying the pinned YAML reader.
    .PARAMETER Directory
    Owned fixture directory below the run directory.
    #>
    param([string]$WorkspaceRoot,[string]$Directory)
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
    $companions=[Collections.Generic.List[string]]::new();$suites=[Collections.Generic.List[string]]::new()
    foreach($name in @('Core')+@(1..119|ForEach-Object {'Companion'+$_.ToString('D3')})){
        $module='FrenchExDev2.QuietCli.'+$name+'.PoSh';$tests='FrenchExDev2.QuietCli.'+$name+'.Tests.PoSh'
        foreach($entry in @(@{Name=$module;Category='src';IsTest=$false},@{Name=$tests;Category='test';IsTest=$true})){
            $path=[IO.Path]::Combine($Directory,'src',$name,$entry.Category,$entry.Name);[void][IO.Directory]::CreateDirectory($path)
            $required=if($entry.IsTest){"@('$module')"}elseif($name -ceq 'Core'){'@()'}else{"@('FrenchExDev2.QuietCli.Core.PoSh')"}
            $exports=if($entry.IsTest){"@('Invoke-Quiet"+$name+"Tests')"}else{'@()'}
            $metadata="SolutionGroup='$name';"+$(if(!$entry.IsTest){"TestsModule='$tests';"}else{''})
            $text="@{RootModule='"+$entry.Name+".psm1';ModuleVersion='1.0.0';RequiredModules=$required;FunctionsToExport=$exports;PrivateData=@{QuietCli=@{$metadata}}}"
            [IO.File]::WriteAllText([IO.Path]::Combine($path,($entry.Name+'.psd1')),$text,[Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText([IO.Path]::Combine($path,($entry.Name+'.psm1')),'# fixture',[Text.UTF8Encoding]::new($false))
            if(!$entry.IsTest){
                $project=[IO.Path]::Combine($path,'engine');[void][IO.Directory]::CreateDirectory($project)
                [IO.File]::WriteAllText([IO.Path]::Combine($project,'Engine.csproj'),('<Project Sdk="Microsoft.NET.Sdk"><PropertyGroup><TargetFramework>net11.0</TargetFramework></PropertyGroup><ItemGroup><PackageReference Include="Fixture.'+$name+'" /></ItemGroup></Project>'),[Text.UTF8Encoding]::new($false))
            }
        }
        $dependency=if($name -ceq 'Core'){'[]'}else{'[Core]'};$image=if($name -ceq 'Core'){'base'}else{'none'}
        $companions.Add("  ${name}:"+[char]10+"    requires: $dependency"+[char]10+"    image: $image")
        $suites.Add("  ${name}:"+[char]10+"    test_project: $tests"+[char]10+"    command: Invoke-Quiet${name}Tests"+[char]10+"    requires: [$name]"+[char]10+"    core_evidence: "+($name -ceq 'Core').ToString().ToLowerInvariant())
    }
    $build=[IO.Path]::Combine($Directory,'build');[void][IO.Directory]::CreateDirectory($build)
    [IO.File]::WriteAllText([IO.Path]::Combine($build,'companions.yml'),('schema: 1'+[char]10+'companions:'+[char]10+($companions -join [char]10)+[char]10+'suites:'+[char]10+($suites -join [char]10)+[char]10),[Text.UTF8Encoding]::new($false))
    $core='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh'
    foreach($relative in @('resources/dependencies.lock.json','resources/yaml/YamlDotNet.dll')){
        $target=[IO.Path]::Combine($Directory,$core,$relative);[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
        Copy-Item -LiteralPath ([IO.Path]::Combine((Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $core),$relative)) -Destination $target
    }
    $central='<Project><PropertyGroup><ManagePackageVersionsCentrally>true</ManagePackageVersionsCentrally></PropertyGroup><ItemGroup><PackageVersion Include="Fixture.Companion053" Version="1.0.0" /></ItemGroup></Project>'
    [IO.File]::WriteAllText([IO.Path]::Combine($Directory,'Directory.Packages.props'),$central,[Text.UTF8Encoding]::new($false))
    $Directory
}

function Invoke-QuietWorkspaceLayoutTests {
    <#
    .SYNOPSIS
    Checks solution/profile generation, 120-companion isolation, malformed XML and targeted mutations.
    .PARAMETER WorkspaceRoot
    Checkout under test.
    .PARAMETER RunDirectory
    Owned evidence directory.
    .PARAMETER OnProgress
    Classified case progress with actual counters.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[scriptblock]$OnProgress)
    foreach($library in @('WorkspaceProjects','WorkspaceSolutions','CompanionWorkflows','CiImpact','CiProjectGraph','CiPlanResults','SourceIdentity','WorkspaceJson')){
        Import-Module ([IO.Path]::Combine($WorkspaceRoot,('scripts/lib/'+$library+'.psm1'))) -Global -DisableNameChecking -ErrorAction Stop
    }
    $fixture=New-QuietLayoutFixture $WorkspaceRoot ([IO.Path]::Combine($RunDirectory,'catalogue'))
    $cases=[ordered]@{};$seed=20261116;$campaign=@{Properties=0;Malformed=0;Killed=0}
    $cases['real membership and generated definitions are complete']={
        $projects=@(Get-QuietWorkspaceProjects $WorkspaceRoot)
        if($projects.Count -ne 8 -or @($projects|Where-Object {$_.Path -cnotmatch '^src/[^/]+/(src|test)/'}).Count){throw 'RealWorkspaceMembershipMismatch'}
        $definitions=@(Get-QuietWorkspaceSolutions $WorkspaceRoot)
        $xml=[xml]($definitions|Where-Object Path -CEQ 'Quietly.slnx').Content
        if($definitions.Count -ne 6 -or @($xml.SelectNodes('//Project')).Count -ne 7){throw 'RealSolutionMembershipMismatch'}
        Sync-QuietWorkspaceSolutions $WorkspaceRoot;Sync-QuietCompanionWorkflows $WorkspaceRoot
        foreach($group in @('Core','Git','Vagrant','Tooling','Distribution')){
            $workflow=if($group -ceq 'Tooling'){'tooling-component-ci.yml'}else{$group.ToLowerInvariant()+'-ci.yml'}
            $plan=Get-QuietCiImpact $WorkspaceRoot @('.github/workflows/'+$workflow)
            if($group -ceq 'Tooling'){if(!$plan.RunTooling -or $plan.RunProducts){throw 'ToolingWorkflowScopeLeaked'}}
            elseif($group -ceq 'Distribution'){if(!$plan.RunDistribution -or $plan.RunProducts){throw 'DistributionWorkflowScopeLeaked'}}
            elseif(($plan.FullSuites -join ',') -cne $group){throw ('ProductWorkflowScopeLeaked: '+$group)}
            $campaign.Properties++
        }
    }
    $cases['120 companions preserve selective qualification and dependent smokes']={
        foreach($number in @(1,17,53,88,119)){
            $name='Companion'+$number.ToString('D3')
            $plan=Get-QuietCiImpact $fixture @('src/'+$name+'/src/FrenchExDev2.QuietCli.'+$name+'.PoSh/entry.ps1')
            if(($plan.FullSuites -join ',') -cne $name -or $plan.SmokeSuites.Count){throw ('CompanionSelectionLeaked: '+$name)}
            $campaign.Properties++
        }
        $plan=Get-QuietCiImpact $fixture @('src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/entry.ps1')
        if(($plan.FullSuites -join ',') -cne 'Core' -or $plan.SmokeSuites.Count -ne 119){throw 'CoreMustQualifyOnceAndSmokeDependents'};$campaign.Properties++
    }
    $cases['central packages select their consumers and ignore unused entries']={
        $after=[IO.File]::ReadAllText([IO.Path]::Combine($fixture,'Directory.Packages.props'),[Text.Encoding]::UTF8)
        $plan=Get-QuietCiImpact $fixture @('Directory.Packages.props') @{'Directory.Packages.props'=$after.Replace('1.0.0','0.9.0')}
        if(($plan.FullSuites -join ',') -cne 'Companion053' -or $plan.BuildProjects.Count -ne 1){throw 'CentralPackageConsumerMismatch'}
        $before=$after.Replace('</ItemGroup>','<PackageVersion Include="Unused.Package" Version="1.0.0" /></ItemGroup>')
        $plan=Get-QuietCiImpact $fixture @('Directory.Packages.props') @{'Directory.Packages.props'=$before}
        if($plan.FullSuites.Count -or $plan.BuildProjects.Count){throw 'UnusedPackageTriggeredBuild'};$campaign.Properties+=2
    }
    $cases['generation is deterministic and preview writes nothing']={
        $first=@(Get-QuietWorkspaceSolutions $fixture);$second=@(Get-QuietWorkspaceSolutions $fixture)
        if(($first.Content -join '|') -cne ($second.Content -join '|')){throw 'SolutionGenerationNotDeterministic'}
        Sync-QuietWorkspaceSolutions $fixture -Apply -WhatIf;Sync-QuietCompanionWorkflows $fixture -Apply -WhatIf
        if(Test-Path ([IO.Path]::Combine($fixture,'Quietly.slnx'))){throw 'PreviewCreatedSolution'};$campaign.Properties++
    }
    $cases['inherited build declarations contribute package and project edges']={
        $directory=[IO.Path]::Combine($fixture,'src/Companion017')
        $props=[IO.Path]::Combine($directory,'Directory.Build.props')
        [IO.File]::WriteAllText($props,'<Project><ItemGroup><PackageReference Include="Fixture.Companion053" /><ProjectReference Include="../Companion053/src/FrenchExDev2.QuietCli.Companion053.PoSh/engine/Engine.csproj" /></ItemGroup></Project>',[Text.UTF8Encoding]::new($false))
        try{
            $graph=@(Get-QuietCiProjectGraph $fixture)
            $project=@($graph|Where-Object Group -CEQ 'Companion017')[0]
            if('Fixture.Companion053' -cnotin $project.Packages.Name -or @($project.References).Count -ne 1){throw 'InheritedReferenceMissing'}
            $central=[IO.File]::ReadAllText([IO.Path]::Combine($fixture,'Directory.Packages.props'),[Text.Encoding]::UTF8)
            $plan=Get-QuietCiImpact $fixture @('Directory.Packages.props') @{'Directory.Packages.props'=$central.Replace('1.0.0','0.9.0')}
            if(($plan.FullSuites|Sort-Object) -join ',' -cne 'Companion017,Companion053'){throw 'InheritedPackageConsumerMissing'}
            $campaign.Properties+=2
        }finally{[IO.File]::Delete($props)}
    }
    $cases['one group supports two sources and two registered test modules']={
        foreach($category in @('src','test')){
            $name=if($category -ceq 'src'){'FrenchExDev2.QuietCli.Extra.PoSh'}else{'FrenchExDev2.QuietCli.Extra.Tests.PoSh'}
            $directory=[IO.Path]::Combine($fixture,'src/Companion001',$category,$name);[void][IO.Directory]::CreateDirectory($directory)
            $metadata=if($category -ceq 'src'){"TestsModule='FrenchExDev2.QuietCli.Extra.Tests.PoSh';"}else{"TestCatalogue=@{Runner='Invoke-QuietExtraTests'};"}
            $exports=if($category -ceq 'test'){"@('Invoke-QuietExtraTests')"}else{'@()'}
            $required=if($category -ceq 'test'){"@('FrenchExDev2.QuietCli.Extra.PoSh')"}else{"@('FrenchExDev2.QuietCli.Core.PoSh')"}
            [IO.File]::WriteAllText([IO.Path]::Combine($directory,($name+'.psd1')),("@{RootModule='$name.psm1';ModuleVersion='1.0.0';RequiredModules=$required;FunctionsToExport=$exports;PrivateData=@{QuietCli=@{SolutionGroup='Companion001';$metadata}}}"),[Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText([IO.Path]::Combine($directory,($name+'.psm1')),'# fixture',[Text.UTF8Encoding]::new($false))
        }
        $yaml='  ExtraChecks:'+[char]10+'    test_project: FrenchExDev2.QuietCli.Extra.Tests.PoSh'+[char]10+'    command: Invoke-QuietExtraTests'+[char]10+'    requires: [Companion001]'+[char]10+'    core_evidence: false'+[char]10
        [IO.File]::AppendAllText([IO.Path]::Combine($fixture,'build/companions.yml'),$yaml,[Text.UTF8Encoding]::new($false))
        $members=@(Get-QuietWorkspaceProjects $fixture|Where-Object SolutionGroup -CEQ 'Companion001')
        if($members.Count -ne 4){throw 'MultipleSourceTestMembersMissing'}
        $selection=@(Get-QuietWorkspaceSuiteSelection $fixture -Suite Companion001)
        if($selection.Count -ne 2 -or 'ExtraChecks' -cnotin $selection.Name){throw 'AdditionalTestRunnerNotSelected'}
        $build=@(Get-QuietWorkspaceBuildSelection $fixture -Suite Companion001)
        if('FrenchExDev2.QuietCli.Extra.PoSh' -cnotin $build -or 'FrenchExDev2.QuietCli.Extra.Tests.PoSh' -cnotin $build){throw 'AdditionalModuleBuildMissing'}
        $campaign.Properties+=3
    }
    $cases['the final gate rejects skipped selected work and failed planning']={
        $needs=@{plan=@{result='success';outputs=@{run_products='true';run_smokes='false';run_tooling='false';run_distribution='false'}};'source-checks'=@{result='success'};'layout-tests'=@{result='success'};products=@{result='success'};smokes=@{result='skipped'};'tooling-only'=@{result='skipped'};distribution=@{result='skipped'}}
        $null=Assert-QuietCiPlanResults $needs
        foreach($failure in @('failed','cancelled','skipped')){
            $needs.products.result=$failure;$rejected=$false
            try{$null=Assert-QuietCiPlanResults $needs}catch{$rejected=$true}
            if(!$rejected){throw ('SelectedJobAccepted: '+$failure)};$campaign.Properties++
        }
    }
    $cases['conditional package properties and malformed XML fail independently']={
        $random=[Random]::new($seed)
        foreach($index in 1..48){
            $version=$random.Next(1,1000).ToString()
            $before='<Project><ItemGroup><PackageVersion Include="A" Version="'+$version+'" Condition="''$(TargetFramework)'' == ''net10.0''" /></ItemGroup></Project>'
            $after=$before.Replace('Version="'+$version+'"','Version="'+($version+'1')+'"')
            if((@(Get-QuietChangedPackages $before $after) -join ',') -cne 'a'){throw 'ConditionalPackagePropertyFailed'};$campaign.Properties++
            $bad=if($index%3 -eq 0){'<!DOCTYPE Project [<!ENTITY x SYSTEM "file:///missing">]><Project>&x;</Project>'}elseif($index%3 -eq 1){'<Project><PackageVersion Include="'+$version+'">'}else{'<Project>'+[char]($random.Next(1,8))+'</Project>'}
            $rejected=$false;try{$null=Read-QuietBuildXml $bad}catch{$rejected=$true}
            if(!$rejected){throw 'ExternalEntityAccepted'};$campaign.Malformed++
        }
        foreach($bad in @('../outside','/absolute',('bad'+[char]0))){
            $rejected=$false;try{$null=Get-QuietCiImpact $fixture @($bad)}catch{$rejected=$true}
            if(!$rejected){throw 'UnsafeChangedPathAccepted'};$campaign.Malformed++
        }
    }
    $cases['the scope-expansion mutant is killed']={
        $body='function Get-QuietCiImpact {'+(Get-Command Get-QuietCiImpact).Definition+'}'
        $anchor='$names=@($configuration.Companions.Keys|Where-Object {$selected.Contains($_)})'
        if(!$body.Contains($anchor)){throw 'SelectionMutationAnchorMissing'}
        $module=New-Module -Name SelectionMutant -ScriptBlock ([scriptblock]::Create($body.Replace($anchor,'$names=@($configuration.Suites.Keys)')))
        try{
            & $module {param($root) foreach($name in @('CiCompanions','WorkspaceProjects','CiProjectGraph')){Import-Module ([IO.Path]::Combine($root,('scripts/lib/'+$name+'.psm1'))) -DisableNameChecking -ErrorAction Stop}} $WorkspaceRoot
            $plan=& $module {param($root) Get-QuietCiImpact $root @('src/Companion017/src/FrenchExDev2.QuietCli.Companion017.PoSh/entry.ps1')} $fixture
            if(($plan.FullSuites -join ',') -ceq 'Companion017'){throw 'SelectionMutantSurvived'};$campaign.Killed++
        }finally{Remove-Module $module -ErrorAction SilentlyContinue}
    }
    $results=[Collections.Generic.List[object]]::new();$passed=0;$failed=0
    foreach($name in $cases.Keys){
        if($OnProgress){& $OnProgress $name 'Running' $passed $failed};$errorText=$null
        try{$null=& $cases[$name];$passed++;$caseState='Passed'}catch{$failed++;$caseState='Failed';$errorText=$_.ToString()}
        $results.Add([pscustomobject]@{Name=$name;State=$caseState;Error=$errorText})
        if($OnProgress){& $OnProgress $name $caseState $passed $failed}
    }
    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'layout-campaign.json')) @{Seed=$seed;Properties=$campaign.Properties;MalformedInputs=$campaign.Malformed;KilledMutants=$campaign.Killed;Cases=$results.ToArray()}
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Tooling.Tests.PoSh';Passed=$passed;Failed=$failed;Cases=$results.ToArray();Partial=$false;Incomplete=$false;Skipped=0}
}
Export-ModuleMember -Function Invoke-QuietWorkspaceLayoutTests
