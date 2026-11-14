#requires -Version 7.6
<# .SYNOPSIS
Resolves declared companion requirements and writes optional GitHub outputs and environment controls.
.PARAMETER Suite
Declared test companion or All.
.PARAMETER WorkspaceRoot
Selected checkout.
.PARAMETER RuntimeIdentifier
Selected PowerShell host RID.
.PARAMETER RuntimeMajor
Selected host CLR major.
.PARAMETER OutputPath
Optional GitHub output file; has_core describes selected tests, excluding tool-only dependencies.
.PARAMETER EnvironmentPath
Optional GitHub environment file for subsequent steps.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$Suite='All',[string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier,[int]$RuntimeMajor=[Environment]::Version.Major,[string]$OutputPath,[string]$EnvironmentPath)
$ErrorActionPreference='Stop'
if(!$PSCmdlet.ShouldProcess($WorkspaceRoot,('Resolve companion requirements for '+$Suite))){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiCompanions.psm1')) -DisableNameChecking
$configuration=Read-QuietCiCompanions $WorkspaceRoot
$selection=Resolve-QuietCiCompanions $configuration -Suite $Suite -RuntimeIdentifier $RuntimeIdentifier -RuntimeMajor $RuntimeMajor
$flag=$selection.HasCoreEvidence.ToString().ToLowerInvariant()
if($OutputPath){[IO.File]::AppendAllText($OutputPath,"has_core=$flag`n",[Text.UTF8Encoding]::new($false))}
if($EnvironmentPath){
    $lines=@('QUIETCLI_SUITE_HAS_CORE='+$flag)+@(foreach($key in $selection.Environment.Keys){$key+'='+$selection.Environment[$key]})
    [IO.File]::AppendAllText($EnvironmentPath,($lines -join "`n")+"`n",[Text.UTF8Encoding]::new($false))
}
$selection
