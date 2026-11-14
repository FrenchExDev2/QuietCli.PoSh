#requires -Version 7.6
<#
.SYNOPSIS
Reads one dotenv key or atomically updates its quoted literal value.
.PARAMETER Path
Dotenv path, defaulting to the checkout's .env file.
.PARAMETER Key
Case-sensitive dotenv identifier.
.PARAMETER Value
New single-line literal value; omitted when reading.
.PARAMETER Read
Reads only Key; does not enumerate other values.
#>
[CmdletBinding(SupportsShouldProcess,DefaultParameterSetName='Read')]
param([string]$Path=([IO.Path]::Combine((Split-Path $PSScriptRoot -Parent),'.env')),
    [Parameter(Mandatory)][ValidatePattern('\A[A-Za-z_][A-Za-z0-9_]*\z')][string]$Key,
    [Parameter(Mandatory,ParameterSetName='Set')][AllowEmptyString()][string]$Value,
    [Parameter(ParameterSetName='Read')][switch]$Read)
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/EnvFile.psm1')) -DisableNameChecking -ErrorAction Stop
if($PSCmdlet.ParameterSetName -eq 'Read'){Get-QuietEnvValue -Path $Path -Key $Key;return}
if(!$PSCmdlet.ShouldProcess($Path,('Set dotenv key '+$Key))){return}
Set-QuietEnvValue -Path $Path -Key $Key -Value $Value -Confirm:$false
