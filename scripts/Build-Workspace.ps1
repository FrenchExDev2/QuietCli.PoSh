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
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidateSet('Release','Debug')][string]$Configuration='Release',[Alias('WindowsRuntimeIdentifier')][ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string[]]$RuntimeIdentifier=@('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64'),[switch]$ReadyToRun,[string]$LocalRuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier,[ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string[]]$ReadyToRunRuntimeIdentifier=@(),[switch]$SolutionOnly,[string]$Suite='All')
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Build-Workspace')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
$selectedModules=@(Get-QuietWorkspaceBuildSelection $WorkspaceRoot -Suite $Suite)
$solutionPath=[IO.Path]::Combine($WorkspaceRoot,'Quietly.slnx')
if($Suite -cne 'All'){
    [xml]$selectedSolution=Get-Content -LiteralPath $solutionPath -Raw -Encoding utf8
    $paths=@($selectedSolution.SelectNodes('//Project')|ForEach-Object {$_.GetAttribute('Path').Replace('\','/')}|Where-Object {($_.Split('/')[0]) -cin $selectedModules})
    if(!$paths.Count){throw 'WorkspaceBuildSelectionEmpty'}
    foreach($path in $paths){
        $projectPath=[IO.Path]::Combine($WorkspaceRoot,$path)
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
        $project=$document.CreateElement('Project');$project.SetAttribute('Path',[IO.Path]::GetFullPath(([IO.Path]::Combine($WorkspaceRoot,$path))));$null=$document.DocumentElement.AppendChild($project)
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
$distributions=@(Get-QuietWorkspaceBuildProjects $WorkspaceRoot|Where-Object Package -CIn $selectedModules)
[xml]$solution=Get-Content -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,'Quietly.slnx')) -Raw -Encoding utf8
$solutionProjects=@($solution.SelectNodes('//Project') | ForEach-Object {$_.GetAttribute('Path').Replace('\','/')})
$snapshots=@{}
foreach($distribution in $distributions){
    if($distribution.Project -cnotin $solutionProjects){throw ('WorkspaceBuildProjectNotInSolution: '+$distribution.Project)}
    $snapshots[$distribution.Output]=@(Get-QuietBinaryInputs $WorkspaceRoot $distribution.Project)
}
Invoke-WorkspaceNative dotnet @('build',$solutionPath,'-c',$Configuration,'--nologo') $WorkspaceRoot
foreach($distribution in $distributions){
    # Publish only copies the solution's portable outputs and dependencies; compilation is disabled.
    Invoke-WorkspaceNative dotnet @('publish',([IO.Path]::Combine($WorkspaceRoot,$distribution.Project)),'-f',$distribution.TargetFramework,'-c',$Configuration,'--no-build','-o',([IO.Path]::Combine($WorkspaceRoot,$distribution.Output)),'--nologo') $WorkspaceRoot
    $slots=if($distribution.Package -ceq 'FrenchExDev2.QuietCli.Core.PoSh'){$ReadyToRunRuntimeIdentifier}else{@()}
    Write-QuietBuildManifest $WorkspaceRoot $distribution.Project $distribution.Output -Inputs $snapshots[$distribution.Output] -Configuration $Configuration -ReadyToRunTargets @($slots)
}
# Architecture-specific publications require their own compiler/Crossgen2 settings.
$project='FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
foreach($rid in $ReadyToRunRuntimeIdentifier){
    $output='FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/'+$rid
    $target=Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Rid -CEQ $rid
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $project)
    Invoke-WorkspaceNative dotnet @('publish',([IO.Path]::Combine($WorkspaceRoot,$project)),'-f','net10.0','-c',$Configuration,'-r',$rid,'--self-contained','false',('-p:PlatformTarget='+$target.PlatformTarget),'-p:PublishReadyToRun=true','-o',([IO.Path]::Combine($WorkspaceRoot,$output)),'--nologo') $WorkspaceRoot
    Write-QuietBuildManifest $WorkspaceRoot $project $output -Inputs $inputs -Configuration $Configuration -RuntimeIdentifier $rid -PlatformTarget $target.PlatformTarget -ReadyToRun
}
foreach($rid in $RuntimeIdentifier){
    $project='FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
    $output='FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$rid
    $target=Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Rid -CEQ $rid
    $architecture=$target.PlatformTarget
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $project)
    $publishArguments=@('publish',([IO.Path]::Combine($WorkspaceRoot,$project)),'-f','net11.0','-c',$Configuration,'-r',$rid,'--self-contained','false',('-p:PlatformTarget='+$architecture),'-o',([IO.Path]::Combine($WorkspaceRoot,$output)),'--nologo')
    $precompiled=$rid -in $ReadyToRunRuntimeIdentifier
    $publishArguments+=('-p:PublishReadyToRun='+$precompiled.ToString().ToLowerInvariant())
    Invoke-WorkspaceNative dotnet $publishArguments $WorkspaceRoot
    Assert-QuietRuntimePublication ([IO.Path]::Combine($WorkspaceRoot,$output)) $target
    Write-QuietBuildManifest $WorkspaceRoot $project $output -Inputs $inputs -Configuration $Configuration -RuntimeIdentifier $rid -PlatformTarget $architecture -ReadyToRun:$precompiled
}
