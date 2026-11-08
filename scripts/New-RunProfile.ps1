#requires -Version 7.6
<#
.SYNOPSIS
Creates a run profile: a data-only `<Name>.profile.ps1` binding a script to default arguments.

.PARAMETER Name
Profile name: lowercase letters, digits and hyphens.

.PARAMETER Script
File name of the target script, located in the script directory.

.PARAMETER Parameters
Default arguments. Values may be strings, integers, doubles, booleans or arrays of them. Every key must be a parameter of the target.

.PARAMETER Description
Free text shown by Invoke-RunProfile -List.

.PARAMETER Directory
Profile directory; defaults to scripts/RunProfiles.

.PARAMETER ScriptDirectory
Directory holding the target script; defaults to scripts/.

.PARAMETER Force
Replaces an existing profile.

.PARAMETER LogLevel
Minimum level written to the console.

.PARAMETER LogPath
Optional log file.

.EXAMPLE
./scripts/New-RunProfile.ps1 -Name coldstart-100 -Script Measure-ColdStart.ps1 -Parameters @{ Runs = 100; Warmup = 5 }
#>
using module ./lib/RunLog.psm1
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory, Position = 0)][string]$Name,
    [Parameter(Mandatory, Position = 1)][string]$Script,
    [hashtable]$Parameters = @{},
    [string]$Description = '',
    [string]$Directory,
    [string]$ScriptDirectory,
    [switch]$Force,
    [ValidateSet('Trace', 'Debug', 'Info', 'Warn', 'Error', 'Off')][string]$LogLevel = 'Info',
    [string]$LogPath
)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/RunProfileStore.psm1'), (Join-Path $PSScriptRoot 'lib/RunFormat.psm1')

$logger = New-RunLogger -Level $LogLevel -Component 'new-profile' -LogPath $LogPath
try {
    $logger.Increment('profile.create.requested')
    $profile = @{ SchemaVersion = 1; Name = $Name; Script = $Script; Parameters = $Parameters }
    if ($Description) { $profile.Description = $Description }
    $logger.Debug("validating profile '$Name' for target '$Script' ($($Parameters.get_Count()) parameters)")
    Assert-RunProfile -Profile $profile
    $target = Resolve-RunProfileTarget -Profile $profile -ScriptDirectory $ScriptDirectory
    Assert-RunTargetParameters -TargetPath $target -Parameters $Parameters
    $path = Get-RunProfilePath -Name $Name -Directory $Directory
    if ($PSCmdlet.ShouldProcess($path, 'Write run profile')) {
        $written = $logger.Time('profile.write', { Write-RunProfile -Profile $profile -Directory $Directory -Force:$Force })
        $logger.Increment('profile.create.succeeded')
        $logger.Info("created $written")
        $written
    }
}
catch {
    $logger.Increment('profile.create.failed')
    $logger.Error($_.Exception.Message)
    throw
}
finally {
    foreach ($line in (Format-RunCounters $logger.Snapshot())) { $logger.Debug($line) }
}
