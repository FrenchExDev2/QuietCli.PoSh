# Objectif : Construire le moteur et le producteur C# indépendant avec le SDK .NET 11 RC épinglé.
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
#>
[CmdletBinding()]param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidateSet('Release','Debug')][string]$Configuration='Release',[Alias('WindowsRuntimeIdentifier')][ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string[]]$RuntimeIdentifier=@('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64'))
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Assert-QuietPtyPublications $WorkspaceRoot
foreach($project in @(@{Path='FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj';Output='FrenchExDev2.QuietCli.Core.PoSh/lib/engine'},@{Path='FrenchExDev2.QuietCli.Core.Tests.PoSh/fixture/QuietCli.Fixture.csproj';Output='FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture'},@{Path='FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests/QuietCli.Engine.Tests.csproj';Output='FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/engine-tests'},@{Path='FrenchExDev2.QuietCli.Git.Tests.PoSh/parser-tests/QuietCli.Git.Parser.Tests.csproj';Output='FrenchExDev2.QuietCli.Git.Tests.PoSh/lib/parser-tests'})){
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $project.Path)
    Invoke-WorkspaceNative dotnet @('build',(Join-Path $WorkspaceRoot $project.Path),'-f','net11.0','-c',$Configuration,'-o',(Join-Path $WorkspaceRoot $project.Output),'--nologo') $WorkspaceRoot
    Write-QuietBuildManifest $WorkspaceRoot $project.Path $project.Output -Inputs $inputs -Configuration $Configuration
}
# Build both compatible caller-local Git assemblies, independent from the engine.
foreach($framework in @('net10.0','net11.0')){
    $gitProject='FrenchExDev2.QuietCli.Git.PoSh/engine/QuietCli.Git.Parser.csproj'
    $gitOutput='FrenchExDev2.QuietCli.Git.PoSh/lib/parser/'+$framework
    $gitInputs=@(Get-QuietBinaryInputs $WorkspaceRoot $gitProject)
    Invoke-WorkspaceNative dotnet @('build',(Join-Path $WorkspaceRoot $gitProject),'-f',$framework,'-c',$Configuration,'-o',(Join-Path $WorkspaceRoot $gitOutput),'--nologo') $WorkspaceRoot
    Write-QuietBuildManifest $WorkspaceRoot $gitProject $gitOutput -Inputs $gitInputs -Configuration $Configuration
}
# Build a portable .NET 10 assembly for direct calls from PowerShell 7.6.
$project='FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
$output='FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess'
$inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $project)
Invoke-WorkspaceNative dotnet @('build',(Join-Path $WorkspaceRoot $project),'-f','net10.0','-c',$Configuration,'-o',(Join-Path $WorkspaceRoot $output),'--nologo') $WorkspaceRoot
Write-QuietBuildManifest $WorkspaceRoot $project $output -Inputs $inputs -Configuration $Configuration
foreach($rid in $RuntimeIdentifier){
    $project='FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
    $output='FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$rid
    $target=Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Rid -CEQ $rid
    $architecture=$target.PlatformTarget
    $inputs=@(Get-QuietBinaryInputs $WorkspaceRoot $project)
    Invoke-WorkspaceNative dotnet @('publish',(Join-Path $WorkspaceRoot $project),'-f','net11.0','-c',$Configuration,'-r',$rid,'--self-contained','false',('-p:PlatformTarget='+$architecture),'-o',(Join-Path $WorkspaceRoot $output),'--nologo') $WorkspaceRoot
    Assert-QuietRuntimePublication (Join-Path $WorkspaceRoot $output) $target
    Write-QuietBuildManifest $WorkspaceRoot $project $output -Inputs $inputs -Configuration $Configuration -RuntimeIdentifier $rid -PlatformTarget $architecture
}
