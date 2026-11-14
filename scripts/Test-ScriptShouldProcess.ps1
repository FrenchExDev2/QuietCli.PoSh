#requires -Version 7.6
<#
.SYNOPSIS
Read-only RaC gate for standard WhatIf/Confirm support on new executable PowerShell scripts.
.PARAMETER WorkspaceRoot
Repository with build/script-shouldprocess.json and the PowerShell sources to check.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent))
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/ScriptShouldProcess.psm1')) -DisableNameChecking -ErrorAction Stop
Test-QuietScriptShouldProcessPolicy $WorkspaceRoot
