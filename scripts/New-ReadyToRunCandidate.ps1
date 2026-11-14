#requires -Version 7.6
<#
.SYNOPSIS
Builds a ReadyToRun copy of FrenchExDev2.QuietCli.Core.PoSh for cold-start A/B profiling.

.DESCRIPTION
Copies global.json and the Core module tree into a throwaway directory (the source workspace's own build is
never touched), then republishes only that copy's engine project with -p:PublishReadyToRun=true. This is
intentionally narrower than Build-Workspace.ps1, which needs all four project directories present; a cold-start
candidate only needs the Core module to exist side by side with the untouched baseline build. See
docs/README-readytorun_profiling.md for the statistical protocol this candidate feeds into.

.PARAMETER WorkspaceRoot
Source workspace to copy FrenchExDev2.QuietCli.Core.PoSh and global.json from; left untouched.

.PARAMETER CandidateRoot
New owned destination for the copy; existing paths and workspace overlap are rejected.

.PARAMETER RuntimeIdentifier
RID to publish ReadyToRun for; defaults to the actual host RID, including musl and ARM64.

.PARAMETER Configuration
Build configuration, Release by default.

.OUTPUTS
The candidate module's .psd1 manifest path, to pass as -CandidateModule to Invoke-ColdStartGate.ps1.

.EXAMPLE
$candidate = ./scripts/New-ReadyToRunCandidate.ps1
./scripts/Invoke-ColdStartGate.ps1 -CandidateModule $candidate -CandidateLabel readytorun -Arguments @{ MeasurePackageSize = $true }
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$CandidateRoot = ([IO.Path]::Combine(([IO.Path]::GetTempPath()),'quietcli-r2r-candidate')),
    [ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier = [Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier,
    [ValidateSet('Release', 'Debug')][string]$Configuration = 'Release'
)
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: New-ReadyToRunCandidate')){return}
$ErrorActionPreference = 'Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop

$CandidateRoot=[IO.Path]::GetFullPath($CandidateRoot,$PWD.Path)
$sourceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
if($CandidateRoot -eq [IO.Path]::GetPathRoot($CandidateRoot) -or $sourceRoot.StartsWith($CandidateRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $CandidateRoot.StartsWith($sourceRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $CandidateRoot -eq $sourceRoot){throw 'ReadyToRunCandidateUnsafeDestination'}
if(Test-Path -LiteralPath $CandidateRoot){throw 'ReadyToRunCandidateDestinationExists: choose a new owned directory.'}
New-Item -ItemType Directory -Path $CandidateRoot | Out-Null
Copy-Item ([IO.Path]::Combine($WorkspaceRoot,'global.json')) $CandidateRoot
Copy-Item ([IO.Path]::Combine($WorkspaceRoot,'Directory.Packages.props')) $CandidateRoot
Copy-Item ([IO.Path]::Combine($WorkspaceRoot,'Directory.Build.props')) $CandidateRoot
Copy-Item ([IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.PoSh')) ([IO.Path]::Combine($CandidateRoot,'FrenchExDev2.QuietCli.Core.PoSh')) -Recurse

$project = 'FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
$output = 'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/'+$RuntimeIdentifier
$inputs = @(Get-QuietBinaryInputs $CandidateRoot $project)
$null = Invoke-WorkspaceNative dotnet @('publish', ([IO.Path]::Combine($CandidateRoot,$project)), '-f', 'net10.0', '-c', $Configuration, '-r', $RuntimeIdentifier, '--self-contained', 'false', '-p:PublishReadyToRun=true', '-o', ([IO.Path]::Combine($CandidateRoot,$output)), '--nologo') $CandidateRoot
$target=Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Rid -CEQ $RuntimeIdentifier
Write-QuietBuildManifest $CandidateRoot $project $output -Inputs $inputs -Configuration $Configuration -RuntimeIdentifier $RuntimeIdentifier -PlatformTarget $target.PlatformTarget -ReadyToRun
$portable=[IO.Path]::Combine($CandidateRoot,'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess/build-manifest.json')
$manifest=Get-Content -LiteralPath $portable -Raw -Encoding utf8|ConvertFrom-Json -AsHashtable
$manifest.ReadyToRunTargets=@($RuntimeIdentifier)
Write-WorkspaceJson $portable $manifest

$manifestPath = [IO.Path]::Combine($CandidateRoot,'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "ReadyToRunCandidateManifestMissing: $manifestPath" }
Write-Output $manifestPath
