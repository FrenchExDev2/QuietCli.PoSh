#requires -Version 7.6
<#
.SYNOPSIS
Builds the solution and prepares declared distributions; does not run tests or publish packages.
.PARAMETER WorkspaceRoot
Monorepo containing global.json, Quietly.slnx and discovered module manifests.
.PARAMETER Configuration
Build configuration, Release by default.
.PARAMETER RuntimeIdentifier
Engine distributions to embed. Windows and Linux x64/ARM64, including musl, are published by default.
.PARAMETER ReadyToRun
Publishes RID-specific net10.0 and net11.0 engines with Crossgen2. Portable IL fallbacks remain available.
.PARAMETER ReadyToRunRuntimeIdentifier
RIDs to precompile. Defaults to LocalRuntimeIdentifier; the Windows x64 package job selects all six RIDs.
.PARAMETER LocalRuntimeIdentifier
Default ReadyToRun target, taken from the actual host runtime (including musl).
.PARAMETER SolutionOnly
Rebuilds Quietly.slnx without publishing distributions or updating package binaries.
.PARAMETER Suite
Builds only the selected test suite and its transitive module dependencies. All builds the complete solution.
.PARAMETER Project
Explicit affected project paths from the CI graph; each must belong to the selected module closure.
.PARAMETER ReuseVerifiedBuild
Reuses verified distributions while restoring the selected solution's package graph for downstream offline tests.
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidateSet('Release','Debug')][string]$Configuration='Release',[Alias('WindowsRuntimeIdentifier')][ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string[]]$RuntimeIdentifier=@('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64'),[switch]$ReadyToRun,[string]$LocalRuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier,[ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string[]]$ReadyToRunRuntimeIdentifier=@(),[switch]$SolutionOnly,[string]$Suite='All',[switch]$ReuseVerifiedBuild,[string[]]$Project=@())
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop

if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Build-Workspace')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspacePublication.psm1')) -DisableNameChecking -ErrorAction Stop
$selectedModules=@(Get-QuietWorkspaceBuildSelection $WorkspaceRoot -Suite $Suite)
$declaredProjectPaths=@(Get-QuietWorkspaceBuildProjects $WorkspaceRoot|Where-Object Package -CIn $selectedModules|Select-Object -ExpandProperty Project -Unique)
$unpublishedRequests=@($Project|Where-Object {$_ -cnotin $declaredProjectPaths})
if($ReadyToRun -and !$ReadyToRunRuntimeIdentifier.Count){$ReadyToRunRuntimeIdentifier=@($LocalRuntimeIdentifier)}
$reuseComplete=$false
if($ReuseVerifiedBuild -and !$SolutionOnly -and !$unpublishedRequests.Count){
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CompanionBuildCache.psm1')) -DisableNameChecking -ErrorAction Stop
    $reuseComplete=Test-QuietReusableBuild -WorkspaceRoot $WorkspaceRoot -Modules $selectedModules -Configuration $Configuration -RuntimeIdentifier $RuntimeIdentifier -ReadyToRunRuntimeIdentifier $ReadyToRunRuntimeIdentifier
}
$solutionPath=[IO.Path]::Combine($WorkspaceRoot,'Quietly.slnx')
if($Suite -cne 'All'){
    [xml]$selectedSolution=Get-Content -LiteralPath $solutionPath -Raw -Encoding utf8
    $selectedRoots=@(Get-QuietWorkspaceProjects $WorkspaceRoot | Where-Object Name -CIn $selectedModules | ForEach-Object {$_.Path+'/'})
    $paths=@($selectedSolution.SelectNodes('//Project')|ForEach-Object {$_.GetAttribute('Path').Replace('\','/')}|Where-Object {$candidate=$_;@($selectedRoots|Where-Object {$candidate.StartsWith($_,[StringComparison]::Ordinal)}).Count -gt 0})
    if(!$paths.Count){throw 'WorkspaceBuildSelectionEmpty'}
    foreach($path in $paths){
        $projectPath=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $path)
        $projectXml=[xml]::new();$projectXml.XmlResolver=$null;$projectXml.LoadXml([IO.File]::ReadAllText($projectPath,[Text.Encoding]::UTF8))
        foreach($reference in $projectXml.SelectNodes('//ProjectReference')){
            $resolved=[IO.Path]::GetFullPath($reference.GetAttribute('Include'),[IO.Path]::GetDirectoryName($projectPath))
            $relative=[IO.Path]::GetRelativePath($WorkspaceRoot,$resolved).Replace('\','/')
            if($relative -cnotin $paths){throw ('WorkspaceBuildUndeclaredProjectReference: '+$relative)}
        }
    }
    $solutionDirectory=[IO.Path]::Combine($WorkspaceRoot,('artifacts/build-selection/'+[guid]::NewGuid().ToString('N')))
    [void][IO.Directory]::CreateDirectory($solutionDirectory)
    $solutionPath=[IO.Path]::Combine($solutionDirectory,'Selected.slnx')
    $document=[xml]::new();$document.XmlResolver=$null;$document.LoadXml('<Solution />')
    foreach($path in $paths){
        $buildProject=$document.CreateElement('Project');$buildProject.SetAttribute('Path',[IO.Path]::GetFullPath(((Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $path))));$null=$document.DocumentElement.AppendChild($buildProject)
    }
    [IO.File]::WriteAllText($solutionPath,$document.OuterXml,[Text.UTF8Encoding]::new($false))
}
if($SolutionOnly){
    if($ReadyToRun -or $ReadyToRunRuntimeIdentifier.Count -or $PSBoundParameters.ContainsKey('RuntimeIdentifier') -or $PSBoundParameters.ContainsKey('LocalRuntimeIdentifier')){throw 'SolutionOnlyDoesNotPublishRuntimeTargets'}
    Invoke-WorkspaceNative dotnet @('build',$solutionPath,'-c',$Configuration,'--nologo') $WorkspaceRoot
    return
}
if($ReadyToRun -and !$ReadyToRunRuntimeIdentifier.Count){$ReadyToRunRuntimeIdentifier=@($LocalRuntimeIdentifier)}
foreach($rid in $ReadyToRunRuntimeIdentifier){if($rid -notin $RuntimeIdentifier){throw ('ReadyToRunTargetNotPublished: '+$rid)}}
if(!$ReadyToRun -and $ReadyToRunRuntimeIdentifier.Count){throw 'ReadyToRunSwitchRequired'}
Assert-QuietPtyPublications $WorkspaceRoot
[xml]$membership=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'Quietly.slnx')) -Raw -Encoding utf8
$selectedRoots=@(Get-QuietWorkspaceProjects $WorkspaceRoot|Where-Object Name -CIn $selectedModules|ForEach-Object {$_.Path+'/'})
foreach($requested in $Project){
    if($requested -cnotin @($membership.SelectNodes('//Project')|ForEach-Object {$_.GetAttribute('Path')}) -or !@($selectedRoots|Where-Object {$requested.StartsWith($_,[StringComparison]::Ordinal)}).Count){throw ('WorkspaceRequestedProjectOutsideSelection: '+$requested)}
}
if($ReuseVerifiedBuild){
    # Binary caches do not contain obj/project.assets.json. Restore the full selected
    # closure before reducing compilation to stale/unpublished projects or returning.
    Invoke-WorkspaceNative dotnet @('restore',$solutionPath,('-p:Configuration='+$Configuration),'--nologo') $WorkspaceRoot
    if($reuseComplete){Write-Host ('Summary: Reused verified build for '+$Suite);return}
}
$distributions=@(Get-QuietWorkspaceBuildProjects $WorkspaceRoot|Where-Object Package -CIn $selectedModules)
if($ReuseVerifiedBuild){
    $distributions=@($distributions|Where-Object {
        try{(Test-QuietBuildManifest $WorkspaceRoot $_.Output).Configuration -cne $Configuration}catch{$true}
    })
    $staleProjects=@(@($distributions.Project)+@($unpublishedRequests)|Sort-Object -Unique)
    if($staleProjects.Count){
        $selectionDirectory=[IO.Path]::Combine($WorkspaceRoot,('artifacts/build-selection/'+[guid]::NewGuid().ToString('N')))
        [void][IO.Directory]::CreateDirectory($selectionDirectory)
        $solutionPath=[IO.Path]::Combine($selectionDirectory,'Stale.slnx')
        $selection=[xml]::new();$selection.XmlResolver=$null;$selection.LoadXml('<Solution />')
        foreach($path in $staleProjects){
            $node=$selection.CreateElement('Project');$node.SetAttribute('Path',[IO.Path]::GetFullPath($path,$WorkspaceRoot));[void]$selection.DocumentElement.AppendChild($node)
        }
        [IO.File]::WriteAllText($solutionPath,$selection.OuterXml,[Text.UTF8Encoding]::new($false))
    }
}
[xml]$solution=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'Quietly.slnx')) -Raw -Encoding utf8
$solutionProjects=@($solution.SelectNodes('//Project') | ForEach-Object {$_.GetAttribute('Path').Replace('\','/')})
$snapshots=@{}
foreach($distribution in $distributions){
    if($distribution.Project -cnotin $solutionProjects){throw ('WorkspaceBuildProjectNotInSolution: '+$distribution.Project)}
    $snapshots[$distribution.Output]=@(Get-QuietBinaryInputs $WorkspaceRoot $distribution.Project)
}
if(!$ReuseVerifiedBuild -or $distributions.Count -or $unpublishedRequests.Count){Invoke-WorkspaceNative dotnet @('build',$solutionPath,'-c',$Configuration,'--nologo') $WorkspaceRoot}
foreach($distribution in $distributions){
    # Publish only copies the solution's portable outputs and dependencies; compilation is disabled.
    Invoke-WorkspacePublication @('publish',((Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $distribution.Project)),'-f',$distribution.TargetFramework,'-c',$Configuration,'--no-build','-o',((Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $distribution.Output)),'--nologo') $WorkspaceRoot
    $slots=if($distribution.Package -ceq 'FrenchExDev2.QuietCli.Core.PoSh'){$ReadyToRunRuntimeIdentifier}else{@()}
    Write-QuietBuildManifest $WorkspaceRoot $distribution.Project $distribution.Output -Inputs $snapshots[$distribution.Output] -Configuration $Configuration -ReadyToRunTargets @($slots)
}
# Architecture-specific publications require their own compiler/Crossgen2 settings.
$buildProject='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
foreach($rid in $ReadyToRunRuntimeIdentifier){
    $output='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/'+$rid
    if($ReuseVerifiedBuild){try{$existing=Test-QuietBuildManifest $WorkspaceRoot $output;if($existing.Configuration -ceq $Configuration -and $existing.ReadyToRun){continue}}catch{}}
    $target=Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Rid -CEQ $rid
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $buildProject)
    Invoke-WorkspacePublication @('publish',((Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $buildProject)),'-f','net10.0','-c',$Configuration,'-r',$rid,'--self-contained','false',('-p:PlatformTarget='+$target.PlatformTarget),'-p:PublishReadyToRun=true','-o',((Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $output)),'--nologo') $WorkspaceRoot
    Write-QuietBuildManifest $WorkspaceRoot $buildProject $output -Inputs $inputs -Configuration $Configuration -RuntimeIdentifier $rid -PlatformTarget $target.PlatformTarget -ReadyToRun
}
foreach($rid in $RuntimeIdentifier){
    $buildProject='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
    $output='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$rid
    if($ReuseVerifiedBuild){try{$existing=Test-QuietBuildManifest $WorkspaceRoot $output;if($existing.Configuration -ceq $Configuration -and ($rid -cnotin $ReadyToRunRuntimeIdentifier -or $existing.ReadyToRun)){continue}}catch{}}
    $target=Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Rid -CEQ $rid
    $architecture=$target.PlatformTarget
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $buildProject)
    $publishArguments=@('publish',((Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $buildProject)),'-f','net11.0','-c',$Configuration,'-r',$rid,'--self-contained','false',('-p:PlatformTarget='+$architecture),'-o',((Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $output)),'--nologo')
    $precompiled=$rid -in $ReadyToRunRuntimeIdentifier
    $publishArguments+=('-p:PublishReadyToRun='+$precompiled.ToString().ToLowerInvariant())
    Invoke-WorkspacePublication $publishArguments $WorkspaceRoot
    Assert-QuietRuntimePublication ((Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $output)) $target
    Write-QuietBuildManifest $WorkspaceRoot $buildProject $output -Inputs $inputs -Configuration $Configuration -RuntimeIdentifier $rid -PlatformTarget $architecture -ReadyToRun:$precompiled
}
