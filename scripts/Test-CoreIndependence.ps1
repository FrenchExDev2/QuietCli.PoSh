#requires -Version 7.6
<#
.SYNOPSIS
Builds Core in an owned source copy containing no real Git companion and runs its qualification.
.PARAMETER WorkspaceRoot
Checkout providing sources and pinned native resources.
.PARAMETER Case
Optional local development filter. Omitted runs the complete Core suite; CI never uses a filter.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$Case)
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,'Copy sources without Git, build Core and run independent qualification')){return}
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
$owner=[guid]::NewGuid().ToString('N')
$evidenceDirectory=Join-Path $WorkspaceRoot ('artifacts/core-independence/'+$owner)
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
if($env:GITHUB_ACTIONS -ceq 'true'){& (Join-Path $directory 'scripts/Initialize-CiEnvironment.ps1') -Target GitHub -ContainerRuntime docker -Confirm:$false|Out-Null}
$previousPath=$env:PATH;$previousDotnetRoot=$env:DOTNET_ROOT
try{
    $localSdk=Get-QuietWorkspaceDotNetHost $WorkspaceRoot
    if($localSdk){$env:PATH=$localSdk.Directory+[IO.Path]::PathSeparator+$env:PATH;$env:DOTNET_ROOT=$localSdk.Directory}
& (Join-Path $directory 'scripts/Build-Workspace.ps1') -WorkspaceRoot $directory -Suite Core -RuntimeIdentifier ([Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier)
if($env:GITHUB_ACTIONS -ceq 'true'){
    if($Case){throw 'CoreIndependenceCiMustBeComplete'}
    & (Join-Path $directory 'scripts/Invoke-GitHubCi.ps1') -WorkspaceRoot $directory -Suite Core -SkipBuild -SkipTty -RunDirectory (Join-Path $directory 'artifacts/tests')
}else{
    $parameters=@{WorkspaceRoot=$directory;Suite='Core';SkipBuild=$true;SkipTty=$true;RunDirectory=(Join-Path $directory 'artifacts/tests')}
    if($Case){$parameters.Case=$Case}
    & (Join-Path $directory 'scripts/Invoke-WorkspaceCi.ps1') @parameters
}
Write-WorkspaceJson (Join-Path $evidenceDirectory 'independence.json') @{GitModulePresent=$false;Suite='Core';Partial=[bool]$Case;Workspace=$directory}
[pscustomobject]@{State='Success';GitModulePresent=$false;Partial=[bool]$Case;Directory=$directory}
}finally{
    $env:PATH=$previousPath;$env:DOTNET_ROOT=$previousDotnetRoot
    $reports=Join-Path $directory 'artifacts/tests'
    if(Test-Path -LiteralPath $reports){Copy-Item -LiteralPath $reports -Destination (Join-Path $evidenceDirectory 'tests') -Recurse}
}
