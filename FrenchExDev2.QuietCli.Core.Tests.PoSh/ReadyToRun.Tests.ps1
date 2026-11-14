function Test-QuietReadyToRun {
    <#
    .SYNOPSIS
    Verifies RID/CLR routing, malformed manifests and build command composition independently.
    .PARAMETER WorkspaceRoot
    Source workspace under test.
    .PARAMETER RunDirectory
    Owned evidence and fixture directory.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory)
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
    . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/src/Protocol.ps1')
    $rids=@((Get-QuietRuntimeTargets $WorkspaceRoot).Rid)
    $fixture=Join-Path $RunDirectory 'readytorun-policy'
    [void][IO.Directory]::CreateDirectory($fixture)
    $properties=0;$malformed=0
    foreach($major in @(10,11,12)){
        $base=if($major -eq 10){'lib/inprocess'}else{'lib/engine'}
        foreach($rid in $rids){
            $slot=Join-Path $fixture ($base+'/'+$rid)
            [void][IO.Directory]::CreateDirectory($slot)
            Write-WorkspaceJson (Join-Path $slot build-manifest.json) @{RuntimeIdentifier=$rid;ReadyToRun=$true}
        }
        foreach($mask in 0..63){
            $selected=@(for($i=0;$i -lt 6;$i++){if($mask -band (1 -shl $i)){$rids[$i]}})
            Write-WorkspaceJson (Join-Path $fixture ($base+'/build-manifest.json')) @{ReadyToRunTargets=$selected}
            foreach($rid in $rids){
                $actual=Resolve-QuietManagedTarget -RuntimeMajor $major -ModuleRoot $fixture -RuntimeIdentifier $rid
                $expected=if($rid -cin $selected){$base+'/'+$rid}else{$base}
                if($actual.Directory -cne $expected -or $actual.Framework -cne $(if($major -eq 10){'net10.0'}else{'net11.0'})){throw 'ReadyToRunRoutingPropertyFailed'}
                $properties++
            }
        }
    }
    foreach($bad in @('{','{"ReadyToRunTargets":null}','{"ReadyToRunTargets":["../escape"]}')){
        Write-WorkspaceJson (Join-Path $fixture lib/inprocess/win-x64/build-manifest.json) @{RuntimeIdentifier='linux-x64';ReadyToRun=$true}
        [void][IO.File]::WriteAllTextAsync((Join-Path $fixture lib/inprocess/build-manifest.json),$bad,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $rejected=$false
        try{$null=Resolve-QuietManagedTarget 10 $fixture $(if($bad.Contains('escape')){'../escape'}else{'win-x64'})}catch{$rejected=$true}
        if(!$rejected){throw 'ReadyToRunMalformedManifestAccepted'};$malformed++
    }
    Write-WorkspaceJson (Join-Path $fixture lib/inprocess/build-manifest.json) @{ReadyToRunTargets=@('win-x64')}
    foreach($bad in @(@{RuntimeIdentifier='linux-x64';ReadyToRun=$true},@{RuntimeIdentifier='win-x64';ReadyToRun=$false})){
        Write-WorkspaceJson (Join-Path $fixture lib/inprocess/win-x64/build-manifest.json) $bad
        $rejected=$false;try{$null=Resolve-QuietManagedTarget 10 $fixture win-x64}catch{$rejected=$true}
        if(!$rejected){throw 'ReadyToRunMismatchedSlotAccepted'};$malformed++
    }
    Write-WorkspaceJson (Join-Path $fixture lib/inprocess/win-x64/build-manifest.json) @{RuntimeIdentifier='win-x64';ReadyToRun=$true}
    $source=(Get-Command Resolve-QuietManagedTarget).ScriptBlock.ToString()
    $mutants=@($source.Replace('if(!$selected){return $target}','if($true){return $target}'),$source.Replace('$target.Directory=$directory','$target.Directory=''lib/engine/win-x64'''))
    foreach($mutant in $mutants){
        $actual=& ([scriptblock]::Create($mutant)) -RuntimeMajor 10 -ModuleRoot $fixture -RuntimeIdentifier win-x64
        if($actual.Directory -ceq 'lib/inprocess/win-x64'){throw 'ReadyToRunRoutingMutantSurvived'}
    }
    $scripts=Join-Path $fixture scripts;[void][IO.Directory]::CreateDirectory($scripts)
    # Replace only the dependency boundary with a lexical fixture; the assertions own its state.
    $buildSource=[IO.File]::ReadAllText([IO.Path]::Combine($WorkspaceRoot,'scripts/Build-Workspace.ps1'),[Text.Encoding]::UTF8)
    if(!$buildSource.Contains("Import-Module ([IO.Path]::Combine(`$PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop")){throw 'BuildFixtureDependencyAnchorMissing'}
    $buildSource=$buildSource.Replace("Import-Module ([IO.Path]::Combine(`$PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop",". ([IO.Path]::Combine(`$PSScriptRoot,'Common.fixture.ps1'))")
    [IO.File]::WriteAllText([IO.Path]::Combine($scripts,'Build-Workspace.ps1'),$buildSource,[Text.UTF8Encoding]::new($false))
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot Quietly.slnx) -Destination $fixture
    $buildDistributions=@(Get-QuietWorkspaceBuildProjects $WorkspaceRoot)
    $FailBuild=$false
    $mock=@'
function Assert-QuietPtyPublications { param($WorkspaceRoot) }
function Get-QuietWorkspaceBuildProjects { param($WorkspaceRoot) $buildDistributions }
function Get-QuietWorkspaceBuildSelection { param($WorkspaceRoot,$Suite) @($buildDistributions.Package|Select-Object -Unique) }
function Assert-QuietRuntimePublication { param($Directory,$Target) }
function Get-QuietBinaryInputs { param($WorkspaceRoot,$Project) ,@{Path='fixture';SHA256='fixture'} }
function Get-QuietRuntimeTargets { param($WorkspaceRoot) foreach($rid in @('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')){[pscustomobject]@{Rid=$rid;PlatformTarget=$(if($rid.EndsWith('arm64')){'ARM64'}else{'x64'})}} }
function Invoke-WorkspaceNative { param($FilePath,$Arguments,$WorkingDirectory) $Commands.Add(@($Arguments));if($FailBuild -and $Arguments[0] -ceq 'build'){throw 'FixtureSolutionBuildFailed'} }
function Write-QuietBuildManifest { param($WorkspaceRoot,$Project,$Output,$Inputs,$Configuration,$RuntimeIdentifier,$PlatformTarget,[switch]$ReadyToRun,$ReadyToRunTargets) }
'@
    [void][IO.File]::WriteAllTextAsync(([IO.Path]::Combine($scripts,'Common.fixture.ps1')),$mock,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    foreach($mask in 0..63){
        $selected=@(for($i=0;$i -lt 6;$i++){if($mask -band (1 -shl $i)){$rids[$i]}})
        $Commands=[Collections.Generic.List[object]]::new()
        & (Join-Path $scripts Build-Workspace.ps1) -WorkspaceRoot $fixture -ReadyToRun:([bool]$mask) -ReadyToRunRuntimeIdentifier $selected
        $compilations=@($Commands | Where-Object {$_[0] -ceq 'build'})
        if($compilations.Count -ne 1 -or $compilations[0][1] -cne (Join-Path $fixture Quietly.slnx) -or $compilations[0] -contains '-o'){throw 'WorkspaceMustCompileSolutionExactlyOnce'}
        $portablePublications=@($Commands | Where-Object {$_ -contains '--no-build'})
        if($portablePublications.Count -ne $buildDistributions.Count){throw 'WorkspacePortablePublicationCountChanged'}
        foreach($distribution in $buildDistributions){
            $matches=@($portablePublications | Where-Object {[IO.Path]::GetFullPath($_[1]) -ceq [IO.Path]::GetFullPath([IO.Path]::Combine($fixture,$distribution.Project)) -and $_[[Array]::IndexOf($_,'-f')+1] -ceq $distribution.TargetFramework -and [IO.Path]::GetFullPath($_[[Array]::IndexOf($_,'-o')+1]) -ceq [IO.Path]::GetFullPath([IO.Path]::Combine($fixture,$distribution.Output))})
            if($matches.Count -ne 1){throw 'WorkspaceDeclaredDistributionNotPreparedExactlyOnce'}
        }
        $precompiled=@($Commands|Where-Object {$_ -contains '-p:PublishReadyToRun=true'})
        if($precompiled.Count -ne 2*$selected.Count){throw 'ReadyToRunBuildCardinalityChanged'}
        foreach($command in $precompiled){
            $target=$command[[Array]::IndexOf($command,'-r')+1]
            if($target -cnotin $selected -or $command -notcontains 'Release'){throw 'ReadyToRunBuildTargetChanged'}
        }
    }
    $Commands=[Collections.Generic.List[object]]::new()
    & (Join-Path $scripts Build-Workspace.ps1) -WorkspaceRoot $fixture -WhatIf
    if($Commands.Count){throw 'WorkspaceBuildWhatIfInvokedNativeTool'}
    & (Join-Path $scripts Build-Workspace.ps1) -WorkspaceRoot $fixture -SolutionOnly
    if($Commands.Count -ne 1 -or $Commands[0][0] -cne 'build' -or $Commands[0][1] -cne (Join-Path $fixture Quietly.slnx)){throw 'WorkspaceSolutionOnlyPreparedDistributions'}
    $Commands=[Collections.Generic.List[object]]::new();$FailBuild=$true
    $rejected=$false;try{& (Join-Path $scripts Build-Workspace.ps1) -WorkspaceRoot $fixture}catch{$rejected=$_.Exception.Message -ceq 'FixtureSolutionBuildFailed'}
    if(!$rejected -or $Commands.Count -ne 1){throw 'WorkspaceBuildContinuedAfterSolutionFailure'}
    $FailBuild=$false
    $portable=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/QuietCli.Engine.dll'
    if(Test-QuietReadyToRunImage $portable){throw 'ReadyToRunPortableFallbackContaminated'}
    $random=[Random]::new(20261110)
    foreach($size in 0..63){
        $bytes=[byte[]]::new($size);$random.NextBytes($bytes)
        $path=Join-Path $fixture malformed.dll;[IO.File]::WriteAllBytes($path,$bytes)
        $accepted=$false;try{$accepted=Test-QuietReadyToRunImage $path}catch{}
        if($accepted){throw 'ReadyToRunMalformedImageAccepted'}
    }
    foreach($job in @('ci.yml','publish-psgallery.yml')){
        $workflow=Get-Content -LiteralPath (Join-Path $WorkspaceRoot ('.github/workflows/'+$job)) -Raw -Encoding utf8
        if($workflow -notmatch 'Build-Workspace.ps1[^\r\n]*-Configuration Release[^\r\n]*-ReadyToRunRuntimeIdentifier'){throw 'ReadyToRunGitHubBuildMissing'}
        if($job -eq 'publish-psgallery.yml' -and $workflow -notmatch 'New-QuietGalleryPackage.ps1[^\r\n]+-RequireReadyToRun'){throw 'ReadyToRunPackageRequirementMissing'}
    }
    $manual=Get-Content -LiteralPath (Join-Path $WorkspaceRoot '.github/workflows/quietcli2-readytorun.yml') -Raw -Encoding utf8
    if($manual -notmatch '(?m)^  workflow_dispatch:' -or $manual -match '(?m)^  (push|pull_request|schedule|workflow_call):' -or $manual -match 'Invoke-ContainerColdStart.ps1|--runtime podman|-PublishCache' -or $manual -notmatch 'Invoke-ContainerColdStartWorker.ps1[^\r\n]+-ContainerRuntime docker'){throw 'ReadyToRunManualWorkflowPolicyChanged'}
    $build=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/build-manifest.json') -Raw -Encoding utf8|ConvertFrom-Json
    $packaged=$false
    if(@($build.ReadyToRunTargets).Count -eq 6){
        $package=Join-Path $RunDirectory 'readytorun-package'
        $result=& (Join-Path $WorkspaceRoot scripts/New-QuietGalleryPackage.ps1) -WorkspaceRoot $WorkspaceRoot -OutputDirectory $package -Prerelease readytorunvalidation -RequireReadyToRun
        if($result.State -cne 'Prepared'){throw 'ReadyToRunPackageNotPrepared'}
        $packaged=$true
    }
    Write-WorkspaceJson (Join-Path $RunDirectory readytorun-campaign.json) @{Seed=20261110;RoutingProperties=$properties;BuildSubsets=64;MalformedManifests=$malformed;MalformedImages=64;MutantsKilled=2;AllRidPackageVerified=$packaged}
}
