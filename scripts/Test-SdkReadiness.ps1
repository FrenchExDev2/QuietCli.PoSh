#requires -Version 7.6
<#
.SYNOPSIS
Reports whether the pinned .NET SDK is current and whether ReadyToRun (Crossgen2) is actually publishable for
every RID that -ReadyToRun on Build-Workspace.ps1 would target, without building, installing or publishing
anything.
.DESCRIPTION
Three independent checks, each best-effort and individually reported as Unknown on failure instead of failing
the whole run:
  1. Pinned SDK (global.json) versus the SDK dotnet actually resolves here (respects rollForward) and versus the
     latest SDK published for that channel.
  2. Installed Microsoft.NETCore.App runtimes, used to find the local runtime version per target framework.
  3. Whether Microsoft.NETCore.App.Crossgen2.<Rid> has a published NuGet version matching that runtime version,
     for net10.0/<LocalRuntimeIdentifier> (the lib/inprocess publication) and net11.0/<RuntimeIdentifier> (every
     lib/engine/<rid> publication).
This never installs an SDK or calls dotnet publish; -Update only prints the commands that would close a gap.
.PARAMETER WorkspaceRoot
QuietCli2 workspace containing global.json and runtime-targets.json.
.PARAMETER RuntimeIdentifier
RIDs to check for the net11.0 lib/engine/<rid> publications. Defaults to Build-Workspace.ps1's own default set.
.PARAMETER LocalRuntimeIdentifier
RID checked for the net10.0 lib/inprocess publication. Defaults to the local Windows architecture, matching
Build-Workspace.ps1's own default; override on Linux (for example linux-x64).
.PARAMETER Offline
Skips every network call (channel lookup, NuGet Crossgen2 listings) and reports those fields as Unknown instead
of failing.
.PARAMETER Update
Performs no install or publish. When set, also prints the exact command for each gap found (SDK behind channel,
Crossgen2 not published for a RID) so the user can run it themselves.
.OUTPUTS
One [pscustomobject] (SchemaVersion 1): Sdk, ReadyToRun (one row per framework/RID pair) and Gaps (string list).
Callers branch on this object instead of re-parsing text; it is also written to the pipeline in every mode.
#>
[CmdletBinding(SupportsShouldProcess)]param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidateSet('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64')][string[]]$RuntimeIdentifier=@('win-x64','win-arm64','linux-x64','linux-arm64','linux-musl-x64','linux-musl-arm64'),
    [string]$LocalRuntimeIdentifier=('win-'+([Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant())),
    [switch]$Offline,
    [switch]$Update
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Test-SdkReadiness.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptTestSdkReadiness @PSBoundParameters
