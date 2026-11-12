#requires -Version 7.6
<#
.SYNOPSIS
Builds Core in an owned source copy containing no real Git companion and runs its qualification.
.PARAMETER WorkspaceRoot
Checkout providing sources and pinned native resources.
.PARAMETER Case
Optional local development filter. Omitted runs the complete Core suite; CI never uses a filter.
.PARAMETER Suite
Core exercises the native product; Distribution exercises all packaging cases once without Git.
.PARAMETER SkipBuild
Distribution only: reuses verified Core/Core.Tests binaries, including all six engine RIDs.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$Case,[ValidateSet('Core','Distribution')][string]$Suite='Core',[switch]$SkipBuild)
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Copy sources without Git, build Core and run independent qualification')){return}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
if($SkipBuild -and $Suite -cne 'Distribution'){throw 'CoreIndependenceReuseRequiresDistributionSuite'}
if($SkipBuild){
    $reused=@(Get-QuietWorkspaceBuildSelection -WorkspaceRoot $WorkspaceRoot -Module FrenchExDev2.QuietCli.Core.Tests.PoSh)
    foreach($output in @(Get-QuietWorkspaceBuildProjects $WorkspaceRoot|Where-Object Package -CIn $reused)){$null=Test-QuietBuildManifest $WorkspaceRoot $output.Output}
    foreach($rid in (Get-QuietRuntimeTargets $WorkspaceRoot).Rid){
        $null=Test-QuietBuildManifest $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/lib/engine/'+$rid)
    }
    $portable=Test-QuietBuildManifest $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess'
    foreach($rid in @($portable.ReadyToRunTargets)){$null=Test-QuietBuildManifest $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/'+$rid)}
}
$owner=[guid]::NewGuid().ToString('N')
$evidenceDirectory=if($env:GITHUB_ACTIONS -ceq 'true'){Join-Path $WorkspaceRoot ('artifacts/core-independence/'+$owner)}else{Join-Path (Get-QuietReportRoot $WorkspaceRoot tests) ('core-independence-'+$owner)}
$directory=Join-Path ([IO.Path]::GetTempPath()) ('qc-core-'+$owner.Substring(0,12))
[void][IO.Directory]::CreateDirectory($directory)
[void][IO.Directory]::CreateDirectory($evidenceDirectory)
$allowed=@('scripts','build','docs','.github')+@(Get-QuietWorkspaceProjects $WorkspaceRoot|Where-Object Name -CNE 'FrenchExDev2.QuietCli.Git.PoSh'|ForEach-Object Name)
foreach($file in Get-QuietSourceFiles $WorkspaceRoot){
    $segments=$file.Path.Split('/')
    if($segments -contains '.env'){continue}
    if($segments.Count -gt 1 -and $segments[0] -cnotin $allowed){continue}
    if($segments.Count -eq 1 -and $file.Path -cnotmatch '\A(?:README.*\.md|AGENTS.*\.md|CREDITS\.md|LICENSE|global\.json|Directory\.(?:Build|Packages)\.props|Quietly\.slnx|repositories\.lock\.json|\.gitignore|\.gitattributes|\.editorconfig)\z'){continue}
    $target=Join-Path $directory $file.Path
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target))
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot $file.Path) -Destination $target
}
if(Test-Path -LiteralPath (Join-Path $directory 'FrenchExDev2.QuietCli.Git.PoSh')){throw 'CoreIndependenceGitSourcePresent'}
if($SkipBuild){
    foreach($name in $reused){
        $lib=Join-Path $WorkspaceRoot ($name+'/lib')
        if(Test-Path -LiteralPath $lib){Copy-Item -LiteralPath $lib -Destination (Join-Path $directory $name) -Recurse}
    }
}
$null=& (Join-Path $directory 'scripts/Update-WorkspaceLock.ps1') -WorkspaceRoot $directory
if($env:GITHUB_ACTIONS -ceq 'true'){& (Join-Path $directory 'scripts/Initialize-CiEnvironment.ps1') -Target GitHub -ContainerRuntime docker -Confirm:$false|Out-Null}
$previousPath=$env:PATH;$previousDotnetRoot=$env:DOTNET_ROOT
try{
    $localSdk=Get-QuietWorkspaceDotNetHost $WorkspaceRoot
    if($localSdk){$env:PATH=$localSdk.Directory+[IO.Path]::PathSeparator+$env:PATH;$env:DOTNET_ROOT=$localSdk.Directory}
if(!$SkipBuild){
    $build=@{WorkspaceRoot=$directory;Suite=$Suite}
    if($Suite -ceq 'Core'){$build.RuntimeIdentifier=@([Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier)}
    & (Join-Path $directory 'scripts/Build-Workspace.ps1') @build
}
if($env:GITHUB_ACTIONS -ceq 'true'){
    if($Case){throw 'CoreIndependenceCiMustBeComplete'}
    & (Join-Path $directory 'scripts/Invoke-GitHubCi.ps1') -WorkspaceRoot $directory -Suite $Suite -SkipBuild -SkipTty -RunDirectory (Join-Path $directory 'artifacts/tests')
}else{
    $parameters=@{WorkspaceRoot=$directory;Suite=$Suite;SkipBuild=$true;SkipTty=$true;RunDirectory=(Join-Path $directory 'artifacts/tests')}
    if($Case){$parameters.Case=$Case}
    & (Join-Path $directory 'scripts/Invoke-WorkspaceCi.ps1') @parameters
}
Write-WorkspaceJson (Join-Path $evidenceDirectory 'independence.json') @{GitModulePresent=$false;Suite=$Suite;ReusedBuild=[bool]$SkipBuild;Partial=[bool]$Case;Workspace=$directory;SourceWorkspace=$WorkspaceRoot;SourceRevision=(Read-QuietRepositoryValue $WorkspaceRoot @('rev-parse','--verify','HEAD'))}
[pscustomobject]@{State='Success';GitModulePresent=$false;Partial=[bool]$Case;Directory=$directory}
}finally{
    $env:PATH=$previousPath;$env:DOTNET_ROOT=$previousDotnetRoot
    $reports=Join-Path $directory 'artifacts/tests'
    if(Test-Path -LiteralPath $reports){Copy-Item -LiteralPath $reports -Destination (Join-Path $evidenceDirectory 'tests') -Recurse}
}
