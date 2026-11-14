#Requires -Version 7.6
<#
.SYNOPSIS
Checks .NET SDK publication, downloads, container platforms and local readiness.
.DESCRIPTION
Returns a structured report. No installation, image pull or source migration occurs.
WhatIf performs no HTTP/native probes, engine imports or report writes.
.PARAMETER Channel
Release channel, default 11.0.
.PARAMETER Preleases
Include previews and release candidates (also accepts Prerelease/Prereleases).
.PARAMETER Rid
SDK archive RIDs to check; defaults to the current host RID.
.PARAMETER Platform
Required image platforms; defaults to Linux amd64 and arm64.
.PARAMETER ImageVariant
Official image tag suffix, for example alpine.
.PARAMETER ProjectPath
Directory used for actual SDK resolution.
.PARAMETER SkipLocal
Only inspect publication; Ready remains false without local evidence.
.PARAMETER ReportPath
Optional JSON report; its parent directory must exist.
.PARAMETER TimeoutSeconds
Per-request HTTP timeout, without retries.
.PARAMETER QuietCliRoot
Selected checkout providing independent process infrastructure for native probes.
.PARAMETER FailIfNotReady
Throw after returning the report if Ready is false, for CI failure propagation.
.EXAMPLE
./scripts/Test-DotNetReadiness.ps1 -Preleases -WhatIf
.EXAMPLE
$report = ./scripts/Test-DotNetReadiness.ps1 -Confirm -ReportPath ./readiness.json
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [ValidatePattern('^[1-9][0-9]*\.[0-9]+$')][string]$Channel = '11.0',
    [Alias('Prerelease','Prereleases')][switch]$Preleases,
    [ValidateNotNullOrEmpty()][string[]]$Rid,
    [ValidateNotNullOrEmpty()][string[]]$Platform,
    [string]$ImageVariant,
    [string]$ProjectPath,
    [switch]$SkipLocal,
    [string]$ReportPath,
    [ValidateRange(1,120)][int]$TimeoutSeconds = 20,
    [string]$QuietCliRoot,
    [switch]$FailIfNotReady
)
$ErrorActionPreference = 'Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/DotNetReadiness.psm1')) -ErrorAction Stop -DisableNameChecking
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Check .NET publication and local readiness and optionally write a report')){return}
$options = @{} + $PSBoundParameters
$null = $options.Remove('FailIfNotReady')
$options.Confirm=$false
$report = Get-DotNetReadiness @options
$report
if ($FailIfNotReady -and !$WhatIfPreference -and !$report.Ready) { throw '.NET readiness is not established. Inspect the returned Checks.' }
