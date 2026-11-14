#requires -Version 7.6
<#
.SYNOPSIS
Runs focused offline .NET tooling campaigns through the shared visible test launcher.
.PARAMETER Suite
Readiness, Provisioning, Layout, Locks, or All (default).
.PARAMETER RunDirectory
Optional new external report directory; the shared temporary report policy is the default.
.PARAMETER TimeoutSeconds
Owned worker deadline, default 120 seconds.
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('Readiness','Provisioning','Layout','Locks','All')][string]$Suite='All',
    [string]$RunDirectory,[ValidateRange(10,600)][int]$TimeoutSeconds=120)
$ErrorActionPreference='Stop'
if(!$PSCmdlet.ShouldProcess($PSCommandPath,"Run focused offline .NET $Suite campaign with the shared monitor")){return}
$arguments=@{Suite='DotNet';DotNetSuite=$Suite;SkipBuild=$true;TimeoutSeconds=$TimeoutSeconds;Confirm=$false}
if($RunDirectory){$arguments.RunDirectory=$RunDirectory}
& ([IO.Path]::Combine($PSScriptRoot,'Invoke-WorkspaceCi.ps1')) @arguments
