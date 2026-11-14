#requires -Version 7.6
<#
.SYNOPSIS
Diagnoses a prepared Linux image without pulling, rebuilding, installing or changing RID guards.
.DESCRIPTION
Runs default and explicit runtime-root controls in one uniquely labelled, networkless disposable container.
Only allowlisted identity/configuration fields and bounded failure diagnostics are saved. The immutable
image ID, source hashes, native asset hashes and cleanup result remain in the report. Success means
the diagnostic completed; inspect Diagnosis.Decision, which is never product qualification.
.PARAMETER Image
Existing local image reference; resolved once to its immutable ID.
.PARAMETER ExpectedRuntimeIdentifier
Portable Linux target from the workspace catalogue.
.PARAMETER RuntimeRoots
Explicit Linux .NET roots compared with the unchanged image default.
.PARAMETER ExpectedRuntimeMajor
Required CLR major for the selected PowerShell host, normally 10 for stable.
.PARAMETER WorkspaceRoot
Workspace supplying diagnostic scripts and verified native resources.
.PARAMETER RunDirectory
New report directory, generated under the shared temporary report root when omitted.
.PARAMETER Headless
CI-only launch without the local Windows monitoring window.
.PARAMETER Worker
Internal background entry point; use the normal launcher locally.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Image,
    [Parameter(Mandatory)][ValidatePattern('^linux-(musl-)?(x64|arm64)$')][string]$ExpectedRuntimeIdentifier,
    [string[]]$RuntimeRoots=@('/usr/lib/dotnet','/usr/share/dotnet'),[ValidateRange(10,99)][int]$ExpectedRuntimeMajor=10,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$RunDirectory,[switch]$Headless,[switch]$Worker)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Invoke-ContainerRuntimeDiagnosis.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptInvokeContainerRuntimeDiagnosis @PSBoundParameters
