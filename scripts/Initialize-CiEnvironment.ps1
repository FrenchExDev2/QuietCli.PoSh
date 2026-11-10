#requires -Version 7.6
<#
.SYNOPSIS
Deterministically writes the selected Local or GitHub container runtime into the checkout's dotenv file.
.PARAMETER WorkspaceRoot
Checkout owning .env; unrelated existing keys remain untouched.
.PARAMETER Target
Local selects Podman on Windows and Linux; GitHub selects Docker.
.PARAMETER ContainerRuntime
Explicit preset override, independent of installed commands or running daemons.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidateSet('Local','GitHub')][string]$Target='Local',
    [ValidateSet('podman','docker')][string]$ContainerRuntime)
$ErrorActionPreference='Stop'
$selected=if($ContainerRuntime){$ContainerRuntime.ToLowerInvariant()}elseif($Target -eq 'GitHub'){'docker'}else{'podman'}
$path=Join-Path ([IO.Path]::GetFullPath($WorkspaceRoot,$PWD.Path)) '.env'
if(!$PSCmdlet.ShouldProcess($path,('Initialize '+$Target+' container runtime '+$selected))){return}
. (Join-Path $PSScriptRoot 'EnvFile.ps1')
$result=Set-QuietEnvValue -Path $path -Key QUIET_CONTAINER_RUNTIME -Value $selected -Confirm:$false
[pscustomobject]@{Target=$Target;ContainerRuntime=$selected;Path=$result.Path;Changed=$result.Changed}
