<#
.SYNOPSIS
Produces readable per-job or combined performance evidence without requiring a CLR trace viewer.
.PARAMETER EvidenceRoot
One published bundle or the directory containing all downloaded matrix bundles.
.PARAMETER OutputDirectory
Report destination; may equal a bundle root, but never a raw report input directory.
.PARAMETER Revision
Expected exact workflow revision.
.PARAMETER ExpectedReports
Required matrix receipt count; zero disables only this cardinality check.
.PARAMETER Suite
Core/All requires integration and profiling; Git-only reports those as outside its scope.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$EvidenceRoot,[string]$OutputDirectory,[string]$Revision,[int]$ExpectedReports=0,[ValidateSet('Core','All','Git','Integration')][string]$Suite='All')
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/New-CorePerformanceReport.psm1')) -DisableNameChecking -ErrorAction Stop
Invoke-QuietScriptNewCorePerformanceReport @PSBoundParameters
