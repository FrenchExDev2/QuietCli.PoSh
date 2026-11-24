#requires -Version 7.6
<#
.SYNOPSIS
Builds a ReadyToRun copy of FrenchExDev2.QuietCli.Core.PoSh for cold-start A/B profiling.

.DESCRIPTION
Copies the compiler policy and the Core module into a separate workspace using the same grouped layout.
Publishes the net10.0 and net11.0 engines with ReadyToRun for the selected RID so that the benchmark uses
the precompiled engine on either supported host CLR. See
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
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop

if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: New-ReadyToRunCandidate')){return}
$ErrorActionPreference = 'Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop

$CandidateRoot=[IO.Path]::GetFullPath($CandidateRoot,$PWD.Path)
$sourceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)
if($CandidateRoot -eq [IO.Path]::GetPathRoot($CandidateRoot) -or $sourceRoot.StartsWith($CandidateRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $CandidateRoot.StartsWith($sourceRoot.TrimEnd('\','/')+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase) -or $CandidateRoot -eq $sourceRoot){throw 'ReadyToRunCandidateUnsafeDestination'}
if(Test-Path -LiteralPath $CandidateRoot){throw 'ReadyToRunCandidateDestinationExists: choose a new owned directory.'}
$moduleName = 'FrenchExDev2.QuietCli.Core.PoSh'
$sourceModule = Resolve-QuietWorkspacePath -WorkspaceRoot $sourceRoot -RelativePath $moduleName
$relativeModule = [IO.Path]::GetRelativePath($sourceRoot,$sourceModule).Replace('\','/')
$candidateModule = [IO.Path]::Combine($CandidateRoot,$relativeModule)
$target = Get-QuietRuntimeTargets $sourceRoot | Where-Object Rid -CEQ $RuntimeIdentifier
[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($candidateModule))
foreach ($file in 'global.json','Directory.Packages.props','Directory.Build.props') {
    Copy-Item -LiteralPath ([IO.Path]::Combine($sourceRoot,$file)) -Destination $CandidateRoot
}
Copy-Item -LiteralPath $sourceModule -Destination $candidateModule -Recurse

$project = "$relativeModule/engine/QuietCli.Engine.csproj"
$inputs = @(Get-QuietBinaryInputs $CandidateRoot $project)
$distributions = [ordered]@{'net10.0'='lib/inprocess'; 'net11.0'='lib/engine'}
foreach ($framework in $distributions.Keys) {
    $distribution = "$relativeModule/$($distributions[$framework])"
    $output = "$distribution/$RuntimeIdentifier"
    $outputPath = [IO.Path]::Combine($CandidateRoot,$output)
    $publishArguments = @('publish', ([IO.Path]::Combine($CandidateRoot,$project)), '-f', $framework,
        '-c', $Configuration, '-r', $RuntimeIdentifier, '--self-contained', 'false',
        ('-p:PlatformTarget=' + $target.PlatformTarget), '-p:PublishReadyToRun=true', '-o', $outputPath, '--nologo')
    $null = Invoke-WorkspaceNative dotnet $publishArguments $CandidateRoot
    Assert-QuietRuntimePublication $outputPath $target
    Write-QuietBuildManifest $CandidateRoot $project $output -Inputs $inputs -Configuration $Configuration -RuntimeIdentifier $RuntimeIdentifier -PlatformTarget $target.PlatformTarget -ReadyToRun
    $portable = [IO.Path]::Combine($CandidateRoot,$distribution,'build-manifest.json')
    $manifest = Get-Content -LiteralPath $portable -Raw -Encoding utf8 | ConvertFrom-Json -AsHashtable
    $manifest.ReadyToRunTargets = @($RuntimeIdentifier)
    Write-WorkspaceJson $portable $manifest
}

$manifestPath = [IO.Path]::Combine($candidateModule,$moduleName+'.psd1')
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "ReadyToRunCandidateManifestMissing: $manifestPath" }
Write-Output $manifestPath
