#requires -Version 7.6
<#
.SYNOPSIS
Validates a module-specific publication tag and optionally writes bounded GitHub job outputs.
.PARAMETER Tag
Exact pushed tag, such as FrenchExDev2.QuietCli.Core.PoSh/v0.2.0-preview; must match its script module and manifest.
.PARAMETER WorkspaceRoot
Selected QuietCli2 source checkout.
.PARAMETER OutputPath
Optional GitHub output file receiving the validated module and version.
.PARAMETER ReadBatch
Reads the annotated tag and verifies every batch tag points to Revision on origin before emitting leader outputs.
.PARAMETER Revision
Exact workflow commit required with ReadBatch. WhatIf makes no Git or remote probes.
#>
[CmdletBinding(SupportsShouldProcess)]
param([Parameter(Mandatory)][string]$Tag,[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$OutputPath,[switch]$ReadBatch,[string]$Revision)
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Get-QuietReleasePlan.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptGetQuietReleasePlan @PSBoundParameters
