#requires -Version 7.6
<#
.SYNOPSIS
Builds the engine and companion C# fixture; does not run tests or publish.
.PARAMETER WorkspaceRoot
Root containing global.json and the four module repositories.
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
#>
[CmdletBinding(SupportsShouldProcess)]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidateSet('Release','Debug')][string]$Configuration='Release',[Alias('WindowsRuntimeIdentifier')][ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string[]]$RuntimeIdentifier=@('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64'),[switch]$ReadyToRun,[string]$LocalRuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier,[ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string[]]$ReadyToRunRuntimeIdentifier=@())
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Build-Workspace')){return}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
if($ReadyToRun -and !$ReadyToRunRuntimeIdentifier.Count){$ReadyToRunRuntimeIdentifier=@($LocalRuntimeIdentifier)}
foreach($rid in $ReadyToRunRuntimeIdentifier){if($rid -notin $RuntimeIdentifier){throw ('ReadyToRunTargetNotPublished: '+$rid)}}
if(!$ReadyToRun -and $ReadyToRunRuntimeIdentifier.Count){throw 'ReadyToRunSwitchRequired'}
Assert-QuietPtyPublications $WorkspaceRoot
foreach($project in @(@{Path='FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj';Output='FrenchExDev2.QuietCli.Core.PoSh/lib/engine'},@{Path='FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture/QuietCli.Fixture.csproj';Output='FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture'},@{Path='FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests/QuietCli.Engine.Tests.csproj';Output='FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/engine-tests'},@{Path='FrenchExDev2.QuietCli.Git.Tests.PoSh/parser-tests/QuietCli.Git.Parser.Tests.csproj';Output='FrenchExDev2.QuietCli.Git.Tests.PoSh/lib/parser-tests'})){
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $project.Path)
    Invoke-WorkspaceNative dotnet @('build',(Join-Path $WorkspaceRoot $project.Path),'-f','net11.0','-c',$Configuration,'-o',(Join-Path $WorkspaceRoot $project.Output),'--nologo') $WorkspaceRoot
    $slots=if($project.Output -ceq 'FrenchExDev2.QuietCli.Core.PoSh/lib/engine'){$ReadyToRunRuntimeIdentifier}else{@()}
    Write-QuietBuildManifest $WorkspaceRoot $project.Path $project.Output -Inputs $inputs -Configuration $Configuration -ReadyToRunTargets @($slots)
}
# Build both compatible caller-local Git assemblies, independent from the engine.
foreach($framework in @('net10.0','net11.0')){
    $toolProject='FrenchExDev2.QuietCli.Core.Tests.PoSh/recall-tools/QuietCli.Recall.Tools.csproj'
    $toolOutput='FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/recall-tools/'+$framework
    $toolInputs=@(Get-QuietBinaryInputs $WorkspaceRoot $toolProject)
    Invoke-WorkspaceNative dotnet @('build',(Join-Path $WorkspaceRoot $toolProject),'-f',$framework,'-c',$Configuration,'-o',(Join-Path $WorkspaceRoot $toolOutput),'--nologo') $WorkspaceRoot
    Write-QuietBuildManifest $WorkspaceRoot $toolProject $toolOutput -Inputs $toolInputs -Configuration $Configuration
    $gitProject='FrenchExDev2.QuietCli.Git.PoSh/engine/QuietCli.Git.Parser.csproj'
    $gitOutput='FrenchExDev2.QuietCli.Git.PoSh/lib/parser/'+$framework
    $gitInputs=@(Get-QuietBinaryInputs $WorkspaceRoot $gitProject)
    Invoke-WorkspaceNative dotnet @('build',(Join-Path $WorkspaceRoot $gitProject),'-f',$framework,'-c',$Configuration,'-o',(Join-Path $WorkspaceRoot $gitOutput),'--nologo') $WorkspaceRoot
    Write-QuietBuildManifest $WorkspaceRoot $gitProject $gitOutput -Inputs $gitInputs -Configuration $Configuration
}
# Build a portable .NET 10 assembly for direct calls from PowerShell 7.6.
# Portable directories must never contain a single platform's native code in a universal package.
$project='FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
$output='FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess'
$inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $project)
Invoke-WorkspaceNative dotnet @('build',(Join-Path $WorkspaceRoot $project),'-f','net10.0','-c',$Configuration,'-o',(Join-Path $WorkspaceRoot $output),'--nologo') $WorkspaceRoot
Write-QuietBuildManifest $WorkspaceRoot $project $output -Inputs $inputs -Configuration $Configuration -ReadyToRunTargets $ReadyToRunRuntimeIdentifier
foreach($rid in $ReadyToRunRuntimeIdentifier){
    $output='FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/'+$rid
    $target=Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Rid -CEQ $rid
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $project)
    Invoke-WorkspaceNative dotnet @('publish',(Join-Path $WorkspaceRoot $project),'-f','net10.0','-c',$Configuration,'-r',$rid,'--self-contained','false',('-p:PlatformTarget='+$target.PlatformTarget),'-p:PublishReadyToRun=true','-o',(Join-Path $WorkspaceRoot $output),'--nologo') $WorkspaceRoot
    Write-QuietBuildManifest $WorkspaceRoot $project $output -Inputs $inputs -Configuration $Configuration -RuntimeIdentifier $rid -PlatformTarget $target.PlatformTarget -ReadyToRun
}
foreach($rid in $RuntimeIdentifier){
    $project='FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
    $output='FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$rid
    $target=Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Rid -CEQ $rid
    $architecture=$target.PlatformTarget
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $project)
    $publishArguments=@('publish',(Join-Path $WorkspaceRoot $project),'-f','net11.0','-c',$Configuration,'-r',$rid,'--self-contained','false',('-p:PlatformTarget='+$architecture),'-o',(Join-Path $WorkspaceRoot $output),'--nologo')
    $precompiled=$rid -in $ReadyToRunRuntimeIdentifier
    $publishArguments+=('-p:PublishReadyToRun='+$precompiled.ToString().ToLowerInvariant())
    Invoke-WorkspaceNative dotnet $publishArguments $WorkspaceRoot
    Assert-QuietRuntimePublication (Join-Path $WorkspaceRoot $output) $target
    Write-QuietBuildManifest $WorkspaceRoot $project $output -Inputs $inputs -Configuration $Configuration -RuntimeIdentifier $rid -PlatformTarget $architecture -ReadyToRun:$precompiled
}
