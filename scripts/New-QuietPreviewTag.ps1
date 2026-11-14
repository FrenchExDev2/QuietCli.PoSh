#requires -Version 7.6
<#
.SYNOPSIS
Creates a local annotated timestamp preview tag or an exact module release tag.
.DESCRIPTION
Without Version, tags the exact HEAD of a clean repository without committing or pushing.
With Version, updates selected manifests, commits, creates annotated tags and pushes unless
NoCommit or NoPush is supplied. Existing release tags are rejected locally and remotely.
WhatIf permits a dirty checkout and uses local metadata only, without writes or network calls.
.PARAMETER WorkspaceRoot
QuietCli2 repository root; defaults to this script's checkout, independently of the current directory.
.PARAMETER Timestamp
Optional reproducible instant; defaults to the current UTC time at invocation.
.PARAMETER Release
Uses the public module namespace and complete manifest version; pushing this tag requests publication.
.PARAMETER Module
Independently versioned source component; release creation requires its public packaging capability.
.PARAMETER Version
Requested version; selects the commit/tag/push release mode instead of legacy local timestamp tagging.
.PARAMETER Preview
Explicit positive preview number, or null to detect the next numeric preview from local and remote tags.
.PARAMETER NextPreview
Detects the next numeric preview independently for every selected package.
.PARAMETER NoCommit
Requires selected manifest versions already committed; skips automatic version edits and commit.
.PARAMETER NoPush
Creates only local tags; still reads remote tags to detect existing identities.
.PARAMETER Remote
Configured Git remote, origin by default.
.PARAMETER Message
Optional release commit message.
.EXAMPLE
./scripts/New-QuietPreviewTag.ps1 -WhatIf
.EXAMPLE
$tag = ./scripts/New-QuietPreviewTag.ps1
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium',DefaultParameterSetName='Local')]
param(
    [string]$WorkspaceRoot = (Split-Path $PSScriptRoot -Parent),
    [Parameter(ParameterSetName='Local')][DateTimeOffset]$Timestamp = [DateTimeOffset]::UtcNow,
    [Parameter(ParameterSetName='Local')][switch]$Release,
    [string[]]$Module=@('Core'),
    [Parameter(Mandatory,ParameterSetName='Publish')][string]$Version,
    [Parameter(ParameterSetName='Publish')][Nullable[int]]$Preview,
    [Parameter(ParameterSetName='Publish')][switch]$NextPreview,
    [Parameter(ParameterSetName='Publish')][switch]$NoCommit,
    [Parameter(ParameterSetName='Publish')][switch]$NoPush,
    [Parameter(ParameterSetName='Publish')][ValidatePattern('\A[A-Za-z0-9][A-Za-z0-9._-]*\z')][string]$Remote='origin',
    [Parameter(ParameterSetName='Publish')][string]$Message
)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/New-QuietPreviewTag.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptNewQuietPreviewTag @PSBoundParameters
