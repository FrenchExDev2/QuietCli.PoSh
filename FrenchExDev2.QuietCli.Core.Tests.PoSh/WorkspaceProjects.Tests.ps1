function New-QuietWorkspaceFixtureProject {
    <#
    .SYNOPSIS
    Creates an inert manifest and a module that would fail if discovery imported it.
    .PARAMETER Root
    Owned fixture directory.
    .PARAMETER Name
    Fixture project name.
    .PARAMETER Dependencies
    Explicit local dependency names.
    .PARAMETER Metadata
    Controlled PowerShell data literal for PrivateData.QuietCli.
    .PARAMETER Command
    Exported companion runner name, if any.
    #>
    param([string]$Root,[string]$Name,[string[]]$Dependencies=@(),[string]$Metadata='@{}',[string]$Command)
    $directory=Join-Path $Root $Name
    [void][IO.Directory]::CreateDirectory($directory)
    $required=($Dependencies | ForEach-Object {"'$_'"}) -join ','
    $exports=if($Command){"'$Command'"}else{''}
    $text="@{ RootModule='$Name.psm1';ModuleVersion='0.1.0';RequiredModules=@($required);FunctionsToExport=@($exports);PrivateData=@{QuietCli=$Metadata} }`n"
    [void][IO.File]::WriteAllTextAsync((Join-Path $directory ($Name+'.psd1')),$text,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    [void][IO.File]::WriteAllTextAsync((Join-Path $directory ($Name+'.psm1')),"throw 'DiscoveryMustNotImportModules'`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
}

function Test-QuietWorkspaceBuildProjects {
    <#
    .SYNOPSIS
    Verifies extensible build declarations with generated consumers, malformed inputs and targeted mutants.
    .PARAMETER WorkspaceRoot
    Real source workspace.
    .PARAMETER RunDirectory
    Owned fixture and evidence directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot scripts/lib/Common.psm1) -DisableNameChecking -ErrorAction Stop
    $sourcePath=Join-Path $WorkspaceRoot scripts/lib/WorkspaceProjects.psm1
    $source=Get-Content -LiteralPath $sourcePath -Raw -Encoding utf8
    $counts=@{Properties=0;Malformed=0;Seed=20261110;MutantsKilled=0}
    $verify={
        param($candidate,$fixture,$counts)
        & {
            param($candidate,$fixture,$counts)
            . $candidate
            $name='FrenchExDev2.QuietCli.Packer.PoSh'
            $metadata="@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{'net10.0'='lib/parser/net10.0';'net11.0'='lib/parser/net11.0'}})}"
            New-QuietWorkspaceFixtureProject $fixture $name -Metadata $metadata
            $directory=Join-Path $fixture ($name+'/engine');[void][IO.Directory]::CreateDirectory($directory)
            $project=Join-Path $directory Packer.csproj
            $xml='<Project><PropertyGroup><TargetFrameworks>net10.0;net11.0</TargetFrameworks></PropertyGroup></Project>'
            [IO.File]::WriteAllText($project,$xml,[Text.UTF8Encoding]::new($false))
            New-QuietWorkspaceFixtureProject $fixture 'FrenchExDev2.QuietCli.Vagrant.PoSh'
            $rows=@(Get-QuietWorkspaceBuildProjects $fixture)
            if($rows.Count -ne 2 -or $rows[0].Package -cne $name -or $rows[0].Project -cne "$name/engine/Packer.csproj" -or $rows[0].TargetFramework -cne 'net10.0' -or $rows[1].Output -cne "$name/lib/parser/net11.0"){throw 'NewConsumerBuildDeclarationNotDiscovered'}
            $random=[Random]::new($counts.Seed)
            for($index=0;$index -lt 32;$index++){
                $leaf='slot'+$random.Next(100000)
                New-QuietWorkspaceFixtureProject $fixture $name -Metadata "@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{'net11.0'='lib/$leaf'}})}"
                $rows=@(Get-QuietWorkspaceBuildProjects $fixture)
                if($rows.Count -ne 1 -or $rows[0].Output -cne "$name/lib/$leaf"){throw 'GeneratedBuildOutputChanged'}
                $counts.Properties++
            }
            foreach($bad in @(
                "@{BuildProjects=@(@{Project='../escape.csproj';Outputs=@{'net11.0'='lib/x'}})}",
                "@{BuildProjects=@(@{Project='engine/Missing.csproj';Outputs=@{'net11.0'='lib/x'}})}",
                "@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{'net9.0'='lib/x'}})}",
                "@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{'NET11.0'='lib/x'}})}",
                "@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{'net11.0'='../escape'}})}",
                "@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{'net11.0'='lib/../escape'}})}",
                "@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{'net11.0'='C:/escape'}})}",
                "@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{'net11.0'='lib/x'};Unexpected=1})}",
                "@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{'net10.0'='lib/same';'net11.0'='lib/same'}})}",
                "@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{'net10.0'='lib/parent';'net11.0'='lib/parent/child'}})}",
                "@{BuildProjects=@(@{Project='engine/Packer.csproj';Outputs=@{}})}",
                "@{BuildProjects=@('garbage')}"
            )){
                New-QuietWorkspaceFixtureProject $fixture $name -Metadata $bad
                $rejected=$false;try{$null=@(Get-QuietWorkspaceBuildProjects $fixture)}catch{$rejected=$true}
                if(!$rejected){throw ('MalformedBuildDeclarationAccepted: '+$bad)}
                $counts.Malformed++
            }
            New-QuietWorkspaceFixtureProject $fixture $name -Metadata $metadata
            [IO.File]::WriteAllText($project,'<!DOCTYPE Project [<!ENTITY x "net11.0">]><Project><TargetFramework>&x;</TargetFramework></Project>',[Text.UTF8Encoding]::new($false))
            $rejected=$false;try{$null=@(Get-QuietWorkspaceBuildProjects $fixture)}catch{$rejected=$_.Exception.Message -eq 'WorkspaceBuildDtdRejected'}
            if(!$rejected){throw 'BuildProjectDtdAccepted'}
            [IO.File]::WriteAllText($project,$xml,[Text.UTF8Encoding]::new($false))
        } $candidate $fixture $counts
    }
    & $verify $sourcePath (Join-Path $RunDirectory build-catalogue) $counts
    $identityRoot=Join-Path $RunDirectory build-catalogue
    foreach($relative in @('global.json','Directory.Packages.props','Directory.Build.props','FrenchExDev2.QuietCli.Core.PoSh/protocol.json','FrenchExDev2.QuietCli.Packer.PoSh/shared/Shared.cs')){
        $path=Join-Path $identityRoot $relative;[void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
        [IO.File]::WriteAllText($path,'fixture',[Text.UTF8Encoding]::new($false))
    }
    $peer=Join-Path $identityRoot 'FrenchExDev2.QuietCli.Packer.PoSh/peer/Peer.csproj';[void][IO.Directory]::CreateDirectory((Split-Path $peer -Parent))
    [IO.File]::WriteAllText($peer,'<Project />',[Text.UTF8Encoding]::new($false))
    $project='FrenchExDev2.QuietCli.Packer.PoSh/engine/Packer.csproj'
    [IO.File]::WriteAllText((Join-Path $identityRoot $project),'<Project><ItemGroup><ProjectReference Include="../peer/Peer.csproj" /><Compile Include="../shared/Shared.cs" /></ItemGroup></Project>',[Text.UTF8Encoding]::new($false))
    $inputs=@(Get-QuietBinaryInputs $identityRoot $project)
    foreach($expected in @('Directory.Build.props','FrenchExDev2.QuietCli.Packer.PoSh/peer/Peer.csproj','FrenchExDev2.QuietCli.Packer.PoSh/shared/Shared.cs')){if($expected -cnotin $inputs.Path){throw ('GenericCompilerDependencyNotHashed: '+$expected)}}
    $before=Get-QuietManifestDigest $inputs
    [IO.File]::WriteAllText((Join-Path $identityRoot Directory.Build.props),'changed policy',[Text.UTF8Encoding]::new($false))
    if((Get-QuietManifestDigest @(Get-QuietBinaryInputs $identityRoot $project)) -ceq $before){throw 'CompilerPolicyChangeDidNotInvalidateManifest'}
    $mutants=@(
        $source.Replace("foreach(`$entry in `$metadata['BuildProjects'])","foreach(`$entry in @())"),
        $source.Replace('if($framework -cnotin $declared)','if($false)'),
        $source.Replace('$outputs.Add($package.Name+''/''+$output)','$true')
    )
    foreach($index in 0..($mutants.Count-1)){
        if($mutants[$index] -ceq $source){throw 'BuildCatalogueMutationAnchorMissing'}
        $candidate=Join-Path $RunDirectory ("build-mutant-$index.ps1")
        [IO.File]::WriteAllText($candidate,$mutants[$index],[Text.UTF8Encoding]::new($false))
        $killed=$false;try{& $verify $candidate (Join-Path $RunDirectory "build-mutant-$index") @{Properties=0;Malformed=0;Seed=$counts.Seed}}catch{$killed=$true}
        if(!$killed){throw 'BuildCatalogueMutantSurvived'};$counts.MutantsKilled++
    }
    Write-WorkspaceJson (Join-Path $RunDirectory workspace-build-projects.json) $counts
}

function Test-QuietWorkspaceProjects {
    <#
    .SYNOPSIS
    Checks independent discovery, package policy, dynamic binding, generated DAGs and targeted mutants.
    .PARAMETER WorkspaceRoot
    Actual source checkout.
    .PARAMETER RunDirectory
    Owned reports and disposable manifest fixtures.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $sourcePath=Join-Path $WorkspaceRoot 'scripts/lib/WorkspaceProjects.psm1'
    $source=[IO.File]::ReadAllTextAsync($sourcePath,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
    $counts=@{Properties=0;FuzzInputs=0;Seed=44183}
    $verify={
        param($candidate,$root,$counts)
        & {
            param($candidate,$root,$counts)
            . $candidate
            $core='FrenchExDev2.QuietCli.Core.PoSh';$coreTests='FrenchExDev2.QuietCli.Core.Tests.PoSh'
            $alpha='FrenchExDev2.QuietCli.Alpha.PoSh';$alphaTests='FrenchExDev2.QuietCli.Alpha.Tests.PoSh'
            $zulu='FrenchExDev2.QuietCli.Zulu.PoSh';$zuluTests='FrenchExDev2.QuietCli.Zulu.Tests.PoSh'
            New-QuietWorkspaceFixtureProject $root $core -Metadata "@{TestsModule='$coreTests';Publishable=`$true;PackageName='QuietCli'}"
            New-QuietWorkspaceFixtureProject $root $coreTests @($core) -Metadata '@{Publishable=$true}' -Command Invoke-QuietCoreTests
            New-QuietWorkspaceFixtureProject $root $alpha @($zulu) -Metadata "@{TestsModule='$alphaTests'}"
            New-QuietWorkspaceFixtureProject $root $alphaTests @($alpha,$coreTests) -Command Invoke-QuietAlphaTests
            New-QuietWorkspaceFixtureProject $root $zulu @($core) -Metadata "@{TestsModule='$zuluTests';Publishable=`$false}"
            New-QuietWorkspaceFixtureProject $root $zuluTests @($zulu,$coreTests) -Command Invoke-QuietZuluTests
            New-QuietWorkspaceFixtureProject (Join-Path $root 'artifacts') 'FrenchExDev2.QuietCli.Hidden.PoSh'
            $projects=@(Get-QuietWorkspaceProjects $root)
            if(($projects.Name -join ',') -cne (@($core,$coreTests,$zulu,$zuluTests,$alpha,$alphaTests) -join ',')){throw 'ProjectDiscoveryOrDependencyOrderChanged'}
            $selected=@(Get-QuietWorkspaceSuiteSelection $root All)
            if(($selected.Name -join ',') -cne 'Core,Zulu,Alpha'){throw 'AllDidNotSelectDeclaredCompanions'}
            $packages=@(Get-QuietWorkspacePackages $root)
            $publishable=@(Get-QuietWorkspacePackages $root -Publishable)
            $excluded=@(Get-QuietWorkspacePackages $root -NonPublishable)
            if($packages.Count -ne 6 -or $publishable.Count -ne 1 -or $publishable[0].Name -cne $core -or $publishable[0].PackageName -cne 'QuietCli' -or $excluded.Count -ne 5){throw 'ExplicitPackagePublicationPolicyLost'}
            if(@($packages | Where-Object {$_.IsTest -and $_.Publishable}).Count -or $packages.Name -contains 'All'){throw 'TestOrSuiteModeBecamePublishable'}
            if(($packages | Where-Object Name -CEQ $alpha).Reason -cne 'PublicationNotDeclared'){throw 'UndeclaredPublicationIsNotDenied'}
            $nimbus='FrenchExDev2.QuietCli.Nimbus.PoSh';$nimbusTests='FrenchExDev2.QuietCli.Nimbus.Tests.PoSh'
            New-QuietWorkspaceFixtureProject $root $nimbus @($core) -Metadata "@{TestsModule='$nimbusTests';Publishable=`$false}"
            New-QuietWorkspaceFixtureProject $root $nimbusTests @($nimbus,$coreTests) -Command Invoke-QuietNimbusTests
            if(@(Get-QuietWorkspaceProjects $root).Count -ne 8 -or (Get-QuietWorkspaceSuiteNames $root -Scope Container) -cnotcontains 'Nimbus'){throw 'NewCompanionWasNotDiscoveredDynamically'}
            $binding=Join-Path $root 'Bind-Suite.ps1'
            $bindingSource="[CmdletBinding()]param([string]`$WorkspaceRoot)`ndynamicparam { . '$candidate'; New-QuietWorkspaceSuiteParameter -WorkspaceRoot `$WorkspaceRoot -Scope Container }`nend { `$PSBoundParameters['Suite'] }`n"
            [void][IO.File]::WriteAllTextAsync($binding,$bindingSource,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            if((& $binding -WorkspaceRoot $root -Suite Nimbus) -cne 'Nimbus'){throw 'DynamicSuiteBindingRejectedNewCompanion'}
            $rejected=$false;try{$null=& $binding -WorkspaceRoot $root -Suite Unknown}catch{$rejected=$true};if(!$rejected){throw 'DynamicSuiteBindingAcceptedUnknownValue'}
            $command=Get-Command $binding -ArgumentList @($root)
            $validation=@($command.Parameters['Suite'].Attributes | Where-Object {$_ -is [Management.Automation.ValidateSetAttribute]})
            if($validation.Count -ne 1 -or $validation[0].ValidValues -cnotcontains 'Nimbus'){throw 'DynamicSuiteCompletionValuesMissing'}
            # A cycle must fail rather than silently returning a partial or alphabetically sorted graph.
            New-QuietWorkspaceFixtureProject $root $core @($alpha) -Metadata "@{TestsModule='$coreTests';Publishable=`$true;PackageName='QuietCli'}"
            $rejected=$false;try{$null=Get-QuietWorkspaceProjects $root}catch{$rejected=$_.Exception.Message -eq 'WorkspaceProjectDependencyCycle'}
            if(!$rejected){throw 'DependencyCycleWasNotRejected'}
            New-QuietWorkspaceFixtureProject $root $core -Metadata "@{TestsModule='$coreTests';Publishable=`$true;PackageName='QuietCli'}"
            $random=[Random]::new($counts.Seed)
            for($round=0;$round -lt 32;$round++){
                $graph=Join-Path $root ('generated-'+$round);$expected=[Collections.Generic.List[string]]::new()
                foreach($index in 0..($random.Next(2,9)-1)){
                    $name='FrenchExDev2.QuietCli.P'+[char](90-$index)+'.PoSh'
                    $dependencies=if($expected.Count){@($expected[$expected.Count-1])}else{@()}
                    New-QuietWorkspaceFixtureProject $graph $name $dependencies
                    $expected.Add($name)
                }
                if((@(Get-QuietWorkspaceProjects $graph).Name -join ',') -cne ($expected -join ',')){throw "GeneratedDependencyPropertyFailed: seed=$($counts.Seed) round=$round"}
                $counts.Properties++
            }
            $badDirectory=Join-Path $root 'FrenchExDev2.QuietCli.Malformed.PoSh'
            [void][IO.Directory]::CreateDirectory($badDirectory)
            $badManifest=Join-Path $badDirectory 'FrenchExDev2.QuietCli.Malformed.PoSh.psd1'
            foreach($malformed in @('', '@{', '@{ RequiredModules = $(throw ''must not execute'') }', '@{ PrivateData = [IO.File]::ReadAllText(''absent'') }')){
                [void][IO.File]::WriteAllTextAsync($badManifest,$malformed,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
                $rejected=$false;try{$null=Get-QuietWorkspaceProjects $root}catch{$rejected=$true};if(!$rejected){throw 'MalformedManifestAccepted'};$counts.FuzzInputs++
            }
            [void][IO.File]::WriteAllBytesAsync($badManifest,[byte[]]@(255)).GetAwaiter().GetResult()
            $rejected=$false;try{$null=Get-QuietWorkspaceProjects $root}catch{$rejected=$true};if(!$rejected){throw 'InvalidUtf8ManifestAccepted'};$counts.FuzzInputs++
        } $candidate $root $counts
    }
    $directory=Join-Path $RunDirectory 'workspace-projects'
    [void][IO.Directory]::CreateDirectory($directory)
    & $verify $sourcePath (Join-Path $directory 'baseline') $counts
    $mutations=@(
        @{Name='omit-local-dependencies';From='$project.Dependencies=@($project.RequiredModules | Where-Object {$names.Contains($_)})';To='$project.Dependencies=@()'},
        @{Name='descend-into-artifacts';From='Get-ChildItem -LiteralPath $root -Directory |';To='Get-ChildItem -LiteralPath $root -Directory -Recurse |'},
        @{Name='return-partial-cycle';From="if(!`$progress){throw 'WorkspaceProjectDependencyCycle'}";To='if(!$progress){return $ordered.ToArray()}'},
        @{Name='publish-test-projects';From='$eligible=!$project.IsTest -and ';To='$eligible='},
        @{Name='publish-undeclared-modules';From='$eligible=!$project.IsTest -and $metadata.ContainsKey(''Publishable'') -and $metadata[''Publishable'']';To='$eligible=!$project.IsTest -and (!$metadata.ContainsKey(''Publishable'') -or $metadata[''Publishable''])'},
        @{Name='remove-suite-validation';From='$attributes.Add([Management.Automation.ValidateSetAttribute]::new([string[]]@(Get-QuietWorkspaceSuiteNames $WorkspaceRoot -Scope $Scope)))';To=''}
    )
    $results=[Collections.Generic.List[object]]::new()
    foreach($mutation in $mutations){
        if(([regex]::Matches($source,[regex]::Escape($mutation.From))).Count -ne 1){throw ('WorkspaceProjectsMutationAnchorInvalid: '+$mutation.Name)}
        $candidate=Join-Path $directory ($mutation.Name+'.ps1')
        [void][IO.File]::WriteAllTextAsync($candidate,$source.Replace($mutation.From,$mutation.To),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $tokens=$null;$errors=$null;$null=[Management.Automation.Language.Parser]::ParseFile($candidate,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw ('WorkspaceProjectsMutantInvalid: '+$mutation.Name)}
        $detected=$false;$detail=$null;try{& $verify $candidate (Join-Path $directory $mutation.Name) @{Properties=0;FuzzInputs=0;Seed=$counts.Seed}}catch{$detected=$true;$detail=$_.Exception.Message}
        $results.Add(@{Name=$mutation.Name;State=if($detected){'Killed'}else{'Survived'};Diagnostic=$detail})
        if(!$detected){throw ('WorkspaceProjectsMutantSurvived: '+$mutation.Name)}
    }
    $report=@{Seed=$counts.Seed;PropertyExecutions=$counts.Properties;FuzzInputs=$counts.FuzzInputs;Mutations=$results.ToArray();SourceSHA256=(Get-FileHash $sourcePath -Algorithm SHA256).Hash;Scope='Inert manifests, dependency graphs, package eligibility and actual dynamic parameter binding; no module import or publication'}
    Write-WorkspaceJson (Join-Path $directory 'summary.json') $report
    [pscustomobject]$report
}
