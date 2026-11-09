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
Throwaway destination for the copy; removed and recreated.

.PARAMETER RuntimeIdentifier
RID to publish ReadyToRun for; defaults to this machine's Windows architecture, or linux-x64 on Linux.

.PARAMETER Configuration
Build configuration, Release by default.

.OUTPUTS
The candidate module's .psd1 manifest path, to pass as -CandidateModule to Invoke-ColdStartGate.ps1.

.EXAMPLE
$candidate = ./scripts/New-ReadyToRunCandidate.ps1
./scripts/Invoke-ColdStartGate.ps1 -CandidateModule $candidate -CandidateLabel readytorun -Arguments @{ MeasurePackageSize = $true }
#>
[CmdletBinding()]
param(
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [string]$CandidateRoot = (Join-Path ([IO.Path]::GetTempPath()) 'quietcli-r2r-candidate'),
    [string]$RuntimeIdentifier = $(
        if ($IsWindows) { 'win-' + [Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant() }
        elseif ($IsLinux) { 'linux-x64' }
        else { throw 'ReadyToRunRuntimeIdentifierRequired: pass -RuntimeIdentifier explicitly on this platform.' }
    ),
    [ValidateSet('Release', 'Debug')][string]$Configuration = 'Release'
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')

Remove-Item -LiteralPath $CandidateRoot -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $CandidateRoot | Out-Null
Copy-Item (Join-Path $WorkspaceRoot 'global.json') $CandidateRoot
Copy-Item (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh') (Join-Path $CandidateRoot 'FrenchExDev2.QuietCli.Core.PoSh') -Recurse

$project = 'FrenchExDev2.QuietCli.Core.PoSh/engine/QuietCli.Engine.csproj'
$output = 'FrenchExDev2.QuietCli.Core.PoSh/lib/inprocess'
$inputs = @(Get-QuietBinaryInputs $CandidateRoot $project)
$null = Invoke-WorkspaceNative dotnet @('publish', (Join-Path $CandidateRoot $project), '-f', 'net10.0', '-c', $Configuration, '-r', $RuntimeIdentifier, '--self-contained', 'false', '-p:PublishReadyToRun=true', '-o', (Join-Path $CandidateRoot $output), '--nologo') $CandidateRoot
Write-QuietBuildManifest $CandidateRoot $project $output -Inputs $inputs -Configuration $Configuration -RuntimeIdentifier $RuntimeIdentifier

$manifestPath = Join-Path $CandidateRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "ReadyToRunCandidateManifestMissing: $manifestPath" }
Write-Output $manifestPath
