#requires -Version 7.6
<#
.SYNOPSIS
Releases modules end to end: version commit on a release/* branch, pull request, required CI, merge commit, then tags.
.DESCRIPTION
Creates release/<components>-<version>-<UTC> from the remote delivery branch, commits the selected version edits
through Commit-Workspace, pushes only that branch through Push-Workspace and opens its pull request. It then polls
the pull request until the required check succeeds. With Merge it merges with a merge commit (no admin bypass,
head commit pinned); otherwise it waits for a manual merge. Finally it creates the annotated release tags on the
merge commit, pushes only those tags, and restores the original branch. Every phase is recorded before and after
its effect in artifacts/releases/<id>/release-flow.json; an interrupted (Ctrl+C), failed or timed-out run is
continued with Resume, which reconciles uncertain effects before acting. WhatIf shows the provisional plan from
local metadata only, without network access or writes.
.PARAMETER WorkspaceRoot
Clean QuietCli2 checkout; defaults to this script's checkout.
.PARAMETER Module
Discovered component aliases, full package names or All.
.PARAMETER Version
Common requested base or full version; preview counters remain independent per package.
.PARAMETER Preview
Explicit positive preview number, or null to detect the next numeric preview from local and remote tags.
.PARAMETER NextPreview
Detects the next numeric preview independently for every selected package.
.PARAMETER Message
Optional release commit message.
.PARAMETER Remote
Configured Git remote, origin by default.
.PARAMETER DeliveryBranch
Protected branch receiving the release pull request, develop by default.
.PARAMETER Resume
Receipt of an unfinished release flow to continue with its recorded request.
.PARAMETER Merge
Merges the pull request with a merge commit once the required check succeeds.
.PARAMETER PollSeconds
Interval between pull request observations, 30 seconds by default.
.PARAMETER TimeoutMinutes
Bound on waiting for the check and the merge, 120 minutes by default; a timeout is resumable.
.EXAMPLE
./scripts/Invoke-QuietRelease.ps1 -Module Core,Git -Version 0.3.0 -NextPreview -Merge -WhatIf
.EXAMPLE
./scripts/Invoke-QuietRelease.ps1 -Module Core,Git -Version 0.3.0 -NextPreview -Merge
.EXAMPLE
./scripts/Invoke-QuietRelease.ps1 -Resume artifacts/releases/<id>/release-flow.json -Merge
#>
[CmdletBinding(SupportsShouldProcess,ConfirmImpact='High',DefaultParameterSetName='Start')]
param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [Parameter(ParameterSetName='Start')][string[]]$Module=@('Core'),
    [Parameter(Mandatory,ParameterSetName='Start')][string]$Version,
    [Parameter(ParameterSetName='Start')][Nullable[int]]$Preview,
    [Parameter(ParameterSetName='Start')][switch]$NextPreview,
    [Parameter(ParameterSetName='Start')][string]$Message,
    [Parameter(ParameterSetName='Start')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
    [Parameter(ParameterSetName='Start')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._/-]*\z')][string]$DeliveryBranch='develop',
    [Parameter(Mandatory,ParameterSetName='Resume')][string]$Resume,
    [switch]$Merge,
    [ValidateRange(5,3600)][int]$PollSeconds=30,
    [ValidateRange(0,1440)][double]$TimeoutMinutes=120
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Invoke-QuietRelease.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptInvokeQuietRelease @PSBoundParameters
