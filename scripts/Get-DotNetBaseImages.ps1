#requires -Version 7.6
<#
.SYNOPSIS
Lists bounded official Debian/Alpine tag metadata without downloading image layers.
.PARAMETER Image
Official repository, debian or alpine.
.PARAMETER Name
Optional Docker Hub tag-name filter, such as bookworm or 3.24.
.PARAMETER Limit
Maximum entries from the first page, default 20; not an exhaustive registry inventory.
#>
[CmdletBinding(SupportsShouldProcess)]
param([ValidateSet('debian','alpine')][string]$Image='debian',[string]$Name,
    [ValidateRange(1,100)][int]$Limit=20)
$ErrorActionPreference='Stop'
if(!$PSCmdlet.ShouldProcess("docker.io/library/$Image",'List official registry tags and reported platforms')){return}
Import-Module (Join-Path $PSScriptRoot 'lib/DotNetLocks.psm1') -ErrorAction Stop
$options=@{}+$PSBoundParameters;$options.Confirm=$false
Get-DotNetBaseImageTags @options
