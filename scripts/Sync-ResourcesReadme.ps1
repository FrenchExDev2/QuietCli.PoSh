#requires -Version 7.6
<#
.SYNOPSIS
Checks or regenerates docs/resources/README.md from resource locks and source references.
.PARAMETER WorkspaceRoot
Repository to inspect.
.PARAMETER Apply
Writes generated documentation through ShouldProcess.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[switch]$Apply)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot ResourceDocumentation.ps1)
$expected=Get-QuietResourceDocumentation $WorkspaceRoot
$credits=@('<!-- credits:begin -->','## Credits','',"This document is covered by the mandatory [CREDITS.md](../../CREDITS.md), which records the licenses of [Git](https://github.com/git/git/blob/master/COPYING), [Vagrant](https://github.com/hashicorp/vagrant/blob/main/LICENSE) and [Microsoft .NET/PowerShell](https://github.com/PowerShell/PowerShell/blob/master/LICENSE.txt).",'<!-- credits:end -->') -join "`n"
$expected+="`n"+$credits+"`n"
$path=Join-Path $WorkspaceRoot docs/resources/README.md
$current=if(Test-Path $path){[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult().Replace("`r`n","`n")}else{$null}
$stale=$current -cne $expected
if($stale -and !$Apply){throw 'ResourcesReadmeStale: run Sync-ResourcesReadme.ps1 -Apply after reviewing resource changes.'}
if($stale -and $PSCmdlet.ShouldProcess($path,'Write resource inventory and dependencies')){
    [void][IO.Directory]::CreateDirectory((Split-Path $path -Parent))
    [void][IO.File]::WriteAllTextAsync($path,$expected,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
}
[pscustomobject]@{Check='Resources';State=$(if($stale -and $WhatIfPreference){'Planned'}else{'Success'});Path=$path;Updated=$stale -and $Apply -and !$WhatIfPreference}
