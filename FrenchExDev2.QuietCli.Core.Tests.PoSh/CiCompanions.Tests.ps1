function Test-QuietCiCompanions {
    <# .SYNOPSIS
    Checks independent integration suites, generated dependency graphs, hostile YAML and image identities.
    .PARAMETER WorkspaceRoot
    Real checkout supplying the library and pinned parser.
    .PARAMETER RunDirectory
    Owned fixture/evidence directory; no registry, container or product module is executed.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    $library=Join-Path $WorkspaceRoot 'scripts/lib/CiCompanions.psm1'
    Import-Module $library
    $configuration=Read-QuietCiCompanions $WorkspaceRoot
    $core=Resolve-QuietCiCompanions $configuration -Suite Core -RuntimeIdentifier win-x64 -RuntimeMajor 11
    if(($core.Images -join ',') -cne 'Core' -or ($core.Dependencies -join ',') -cne 'Core' -or @($core.Environment.Values|Where-Object {$_ -cne '0'}).Count){throw 'CoreTestToolDependencyChanged'}
    $git=Resolve-QuietCiCompanions $configuration -Suite Git -RuntimeIdentifier win-x64 -RuntimeMajor 11
    if($git.HasCoreEvidence -or @($git.Environment.Values|Where-Object {$_ -ceq '1'}).Count -ne 6){throw 'CompanionQualificationControlsChanged'}
    $vagrant=Resolve-QuietCiCompanions $configuration -Suite Vagrant
    if(($vagrant.Images -join ',') -cne 'Core' -or $vagrant.HasCoreEvidence){throw 'VagrantFixtureToolRequirementsChanged'}

    $fixture=Join-Path $RunDirectory 'ci-companions'
    $source=Join-Path $fixture 'source'
    $resourceDirectory=Join-Path $source 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml'
    [void][IO.Directory]::CreateDirectory($resourceDirectory)
    $resource=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'
    Copy-Item -LiteralPath $resource -Destination $resourceDirectory
    Write-WorkspaceJson (Join-Path $source 'FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json') @{Files=@(@{Path='resources/yaml/YamlDotNet.dll';SHA256=(Get-FileHash $resource).Hash})}
    $testProject='FrenchExDev2.QuietCli.Pair.Integration.Tests.PoSh'
    $tests=Join-Path $source $testProject
    [void][IO.Directory]::CreateDirectory($tests)
    $utf8=[Text.UTF8Encoding]::new($false)
    foreach($component in @('Core','Vagrant')){
        $product='FrenchExDev2.QuietCli.'+$component+'.PoSh'
        $testsName='FrenchExDev2.QuietCli.'+$component+'.Tests.PoSh'
        New-QuietWorkspaceFixtureProject $source $product -Metadata ("@{TestsModule='"+$testsName+"'}")
        New-QuietWorkspaceFixtureProject $source $testsName @($product) -Command ('Invoke-Quiet'+$component+'Tests')
    }
    [IO.File]::WriteAllText((Join-Path $tests ($testProject+'.psd1')),"@{ModuleVersion='1.0.0';RootModule='DoNotImport.psm1';FunctionsToExport=@('Invoke-QuietPairTests')}`n",$utf8)
    [IO.File]::WriteAllText((Join-Path $tests 'DoNotImport.psm1'),"throw 'ConfigurationDiscoveryImportedTestCode'`n",$utf8)
    $prefix="schema: 1`ncompanions:`n  Core:`n    requires: []`n    image: base`n  Vagrant:`n    requires: [Core]`n    image: none`n"
    $nodes=[Text.StringBuilder]::new($prefix)
    foreach($index in 1..100){
        $name='Node'+$index.ToString('000')
        $previous=if($index -eq 1){'Core'}else{'Node'+($index-1).ToString('000')}
        [void]$nodes.Append("  ${name}:`n    requires: [$previous]`n    image: none`n")
    }
    $suffix="suites:`n  Core:`n    test_project: FrenchExDev2.QuietCli.Core.Tests.PoSh`n    command: Invoke-QuietCoreTests`n    requires: [Core]`n    core_evidence: false`n  Vagrant:`n    test_project: FrenchExDev2.QuietCli.Vagrant.Tests.PoSh`n    command: Invoke-QuietVagrantTests`n    requires: [Vagrant]`n    core_evidence: false`n  CoreVagrantIntegration:`n    test_project: $testProject`n    command: Invoke-QuietPairTests`n    requires: [Core, Vagrant, Node100]`n    core_evidence: false`n"
    $yaml=$nodes.ToString()+$suffix
    $path=Join-Path $source 'build/companions.yml'
    [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
    [IO.File]::WriteAllText($path,$yaml,$utf8)
    $generated=Read-QuietCiCompanions $source
    $selection=Resolve-QuietCiCompanions $generated -Suite CoreVagrantIntegration
    if($generated.Companions['Core'].requires.Count -or $selection.Dependencies.Count -ne 102 -or ($selection.Images -join ',') -cne 'Core'){throw 'IntegrationSuiteCreatedReverseProductDependency'}
    . (Join-Path $WorkspaceRoot 'scripts/WorkspaceProjects.ps1')
    $runner=@(Get-QuietWorkspaceSuiteSelection $source CoreVagrantIntegration)
    if($runner.Count -ne 1 -or $runner[0].TestsModule -cne $testProject -or $runner[0].Command -cne 'Invoke-QuietPairTests'){throw 'DedicatedIntegrationRunnerNotSelected'}
    $all=Resolve-QuietCiCompanions $generated -Suite All
    if(($all.Selected -join ',') -cne 'Core,Vagrant,CoreVagrantIntegration'){throw 'AllDidNotDiscoverIndependentIntegrationSuite'}
    $random=[Random]::new(20261111);$properties=0
    foreach($round in 1..48){
        $last=$random.Next(1,101)
        $candidate=$yaml.Replace('requires: [Core, Vagrant, Node100]',('requires: [Vagrant, Node'+$last.ToString('000')+', Core]'))
        [IO.File]::WriteAllText($path,$candidate,$utf8)
        $resolved=Resolve-QuietCiCompanions (Read-QuietCiCompanions $source) -Suite CoreVagrantIntegration
        if($resolved.Dependencies.Count -ne $last+2 -or @($resolved.Dependencies|Sort-Object -Unique).Count -ne $last+2 -or $resolved.Dependencies[0] -cne 'Core'){throw 'GeneratedCompanionClosureChanged'}
        foreach($index in 1..$last){if([array]::IndexOf($resolved.Dependencies,('Node'+$index.ToString('000'))) -le [array]::IndexOf($resolved.Dependencies,$(if($index -eq 1){'Core'}else{'Node'+($index-1).ToString('000')}))){throw 'CompanionDependencyOrderChanged'}}
        $properties++
    }
    $invalid=@(
        $yaml.Replace('schema: 1','schema: 2'),
        $yaml.Replace('schema: 1',"schema: '1'"),
        $yaml.Replace('schema: 1','schema: 1.0'),
        $yaml.Replace('schema: 1',"schema: 1`nschema: 1"),
        $yaml.Replace('image: none','image: unexpected'),
        $yaml.Replace('requires: [Core]','requires: [Missing]'),
        $yaml.Replace('requires: []','requires: [Node100]'),
        $yaml.Replace('requires: [Core]','requires: [Vagrant]'),
        $yaml.Replace('command: Invoke-QuietPairTests','command: Invoke-QuietMissingTests'),
        $yaml.Replace($testProject,'../Outside'),
        $yaml.Replace('core_evidence: false','core_evidence: maybe'),
        $yaml.Replace('image: base','image: none'),
        $yaml.Replace('requires: [Core, Vagrant, Node100]','requires: [Core, Missing]'),
        $yaml.Replace('image: base',"image: base`n    shell: 'execute me'")
    )
    foreach($candidate in $invalid){
        [IO.File]::WriteAllText($path,$candidate,$utf8)
        $rejected=$false
        try{$null=Read-QuietCiCompanions $source}catch{$rejected=$true}
        if(!$rejected){throw 'MalformedCompanionDeclarationAccepted'}
    }
    [IO.File]::WriteAllText($path,$yaml,$utf8)
    $module=Get-Module CiCompanions
    $resolverSource=& $module {(Get-Command Resolve-QuietCiCompanions).ScriptBlock.ToString()}
    $anchor='$suites[$name].Requires'
    if(([regex]::Matches($resolverSource,[regex]::Escape($anchor))).Count -ne 1){throw 'CompanionDependencyMutationAnchorChanged'}
    $mutant=[scriptblock]::Create($resolverSource.Replace($anchor,'@($suites[$name].Requires)[0]'))
    $mutated=& $module {param($candidate,$configuration)& $candidate -Configuration $configuration -Suite CoreVagrantIntegration} $mutant $generated
    if($mutated.Dependencies -ccontains 'Vagrant'){throw 'CompanionSuiteRequirementMutantSurvived'}
    . (Join-Path $WorkspaceRoot 'scripts/CiImages.ps1')
    $base=Get-QuietCiImagePlan $WorkspaceRoot linux-x64
    $fragment=[pscustomobject]@{Platform='debian';Objective='Synthetic independent layer';Stages=@([pscustomobject]@{Name='ci';Run=@('true')})}
    $inputPaths=@('build/companions.yml')
    $first=Get-QuietCiModuleImagePlan $WorkspaceRoot linux-x64 First $fragment @{} $inputPaths -ParentPlan $base
    $second=Get-QuietCiModuleImagePlan $WorkspaceRoot linux-x64 Second $fragment @{} $inputPaths -ParentPlan $first
    $changed=$first.PSObject.Copy();$changed.Fingerprint='f'*64
    $next=Get-QuietCiModuleImagePlan $WorkspaceRoot linux-x64 Second $fragment @{} $inputPaths -ParentPlan $changed
    if($second.Fingerprint -ceq $next.Fingerprint){throw 'IntermediateImageChangeDidNotInvalidateChild'}
    $imageSource=(Get-Command Get-QuietCiModuleImagePlan).ScriptBlock.ToString()
    $anchor='$core=if($ParentPlan){$ParentPlan}else{Get-QuietCiImagePlan $WorkspaceRoot $RuntimeIdentifier}'
    if(!$imageSource.Contains($anchor)){throw 'CompanionParentMutationAnchorChanged'}
    $mutant=[scriptblock]::Create($imageSource.Replace($anchor,'$core=Get-QuietCiImagePlan $WorkspaceRoot $RuntimeIdentifier'))
    $bad1=& $mutant $WorkspaceRoot linux-x64 Second $fragment @{} $inputPaths -ParentPlan $first
    $bad2=& $mutant $WorkspaceRoot linux-x64 Second $fragment @{} $inputPaths -ParentPlan $changed
    if($bad1.Fingerprint -cne $bad2.Fingerprint){throw 'CompanionParentFingerprintMutantNotExercised'}
    $imageChecks=& {
        param($WorkspaceRoot)
        . (Join-Path $WorkspaceRoot 'scripts/CiImages.ps1')
        function Invoke-CiProcess {
            <#
            .SYNOPSIS
            Supplies owned parent-image metadata without starting a container process.
            .PARAMETER FilePath
            Container adapter being checked.
            .PARAMETER ArgumentList
            Expected image inspection argument vector.
            .PARAMETER TimeoutSeconds
            Declared inspection deadline.
            .PARAMETER State
            Caller-owned metadata accumulator.
            .PARAMETER OnOutput
            Real image inspection callback under test.
            #>
            param($FilePath,$ArgumentList,$TimeoutSeconds,$State,$OnOutput)
            if($FilePath -cnotin @('docker','podman') -or ($ArgumentList[0..1] -join ',') -cne 'image,inspect'){throw 'UnexpectedImageMetadataOperation'}
            $null=& $OnOutput ([pscustomobject]@{Stream='stdout';Text=($metadata|ConvertTo-Json -Depth 8 -Compress)}) $State
            [pscustomobject]@{Outcome='Success'}
        }
        $checks=0
        foreach($runtime in @('docker','podman')){foreach($architecture in @('x64','arm64')){
            $plan=[pscustomobject]@{Architecture=$architecture;Fingerprint=('a'*64);Source='https://example.invalid/source'}
            $labels=@{'org.frenchexdev.quietcli2.inputs'=('a'*64);'org.opencontainers.image.source'=$plan.Source}
            $metadata=@{Id=('sha256:'+('1'*64));Architecture=$(if($architecture -ceq 'x64'){'amd64'}else{'arm64'});Os='linux'}
            if($runtime -ceq 'podman'){$metadata.Labels=$labels}else{$metadata.Config=@{Labels=$labels}}
            $valid=Get-QuietCiVerifiedImage -Plan $plan -Reference 'synthetic-parent' -ContainerRuntime $runtime
            if($valid.Id -cne ('sha256:'+('1'*64))){throw 'PreparedParentIdentityChanged'}
            foreach($damage in @('architecture','os','id','fingerprint','source')){
                $good=$metadata|ConvertTo-Json -Depth 8 -Compress
                switch($damage){
                    architecture {$metadata.Architecture='wrong'}
                    os {$metadata.Os='windows'}
                    id {$metadata.Id='mutable:tag'}
                    fingerprint {$labels['org.frenchexdev.quietcli2.inputs']='b'*64}
                    source {$labels['org.opencontainers.image.source']='https://example.invalid/other'}
                }
                $rejected=$false
                try{$null=Get-QuietCiVerifiedImage -Plan $plan -Reference 'synthetic-parent' -ContainerRuntime $runtime}catch{$rejected=$_.Exception.Message -ceq 'CiImageIdentityMismatch'}
                if(!$rejected){throw ('DamagedParentImageAccepted: '+$damage)}
                $metadata=$good|ConvertFrom-Json -AsHashtable
                $labels=if($runtime -ceq 'podman'){$metadata.Labels}else{$metadata.Config.Labels}
                $checks++
            }
        }}
        $imageSource=(Get-Command Get-QuietCiVerifiedImage).ScriptBlock.ToString()
        $anchor='$labels.''org.frenchexdev.quietcli2.inputs'' -cne $Plan.Fingerprint'
        if(!$imageSource.Contains($anchor)){throw 'ParentLabelMutationAnchorMissing'}
        $mutant=[scriptblock]::Create($imageSource.Replace($anchor,'$false'))
        $labels['org.frenchexdev.quietcli2.inputs']='b'*64
        $accepted=& $mutant -Plan $plan -Reference 'synthetic-parent' -ContainerRuntime $runtime
        if($accepted.Id -cne ('sha256:'+('1'*64))){throw 'ParentLabelMutantNotExercised'}
        $checks
    } $WorkspaceRoot
    foreach($script in @('Initialize-CiCompanions.ps1','New-CiSuiteImage.ps1')){
        $missing=Join-Path $fixture 'absent-checkout'
        if($script -ceq 'Initialize-CiCompanions.ps1'){$null=& (Join-Path $WorkspaceRoot ('scripts/'+$script)) -WorkspaceRoot $missing -OutputPath (Join-Path $missing 'output.txt') -WhatIf}
        else{$null=& (Join-Path $WorkspaceRoot ('scripts/'+$script)) -WorkspaceRoot $missing -RuntimeIdentifier linux-arm64 -WhatIf}
        if(Test-Path -LiteralPath $missing){throw 'CompanionPreviewCreatedFiles'}
    }
    $null=Invoke-QuietCiSuiteImage -WorkspaceRoot $missing -Selection $selection -RuntimeIdentifier linux-arm64 -WhatIf
    if(Test-Path -LiteralPath $missing){throw 'CompanionLibraryPreviewCreatedFiles'}
    $entry=[IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.github/workflows/companions-ci.yml'),[Text.Encoding]::UTF8)
    $workflow=[YamlDotNet.Serialization.DeserializerBuilder]::new().Build().Deserialize($entry)
    if(!$workflow['on'].ContainsKey('pull_request') -or $null -ne $workflow['on']['pull_request'] -or !$workflow['jobs'].ContainsKey('plan') -or
        $workflow['jobs']['companions']['with']['suite'] -cne '${{ needs.plan.outputs.suite }}' -or
        $workflow['jobs']['ci-status']['name'] -cne 'QuietCli required CI' -or
        (Test-Path (Join-Path $WorkspaceRoot '.github/workflows/git-ci.yml')) -or (Test-Path (Join-Path $WorkspaceRoot '.github/workflows/core-ci.yml'))){throw 'PerCompanionEntryWorkflowRequired'}
    Write-WorkspaceJson (Join-Path $RunDirectory 'ci-companions.json') @{Seed=20261111;GeneratedCompanions=100;DependencyProperties=$properties;MalformedYamlInputs=$invalid.Count;ParentIdentityRejections=$imageChecks;MutantsKilled=3;DedicatedIntegrationRunner=$true;ReverseCoreDependency=$false;NativeExecutions=0;SourceSHA256=(Get-FileHash $library).Hash}
}
