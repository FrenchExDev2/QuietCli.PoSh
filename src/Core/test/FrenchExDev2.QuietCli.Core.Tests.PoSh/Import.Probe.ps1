#requires -Version 7.6
<#
.SYNOPSIS
Measures one inert import in a fresh, deliberately profile-free PowerShell process.
.PARAMETER Manifest
Absolute local Core manifest, including for the baseline identity.
.PARAMETER Mode
Baseline performs no import; Import loads the explicit local manifest once.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Manifest,[ValidateSet('Baseline','Import')][string]$Mode)
$ErrorActionPreference='Stop'
$utf8=[Text.UTF8Encoding]::new($false)
[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
if(Get-Module FrenchExDev2.QuietCli.Core.PoSh){throw 'ContaminatedImportProbe'}
if([AppDomain]::CurrentDomain.GetAssemblies().GetName().Name -match '^QuietCli2'){throw 'ContaminatedImportAssembly'}
$process=[Diagnostics.Process]::GetCurrentProcess()
try{
    # Warm measurement APIs equally in both arms; do not force a GC or start an engine.
    $process.Refresh();$null=$process.TotalProcessorTime
    $null=[GC]::GetTotalAllocatedBytes($false);$null=[GC]::GetTotalMemory($false)
    $watch=[Diagnostics.Stopwatch]::new()
    $cpu=$process.TotalProcessorTime.TotalMilliseconds
    $working=$process.WorkingSet64;$private=$process.PrivateMemorySize64
    $managed=[GC]::GetTotalMemory($false);$allocated=[GC]::GetTotalAllocatedBytes($false)
    $watch.Start()
    if($Mode -eq 'Import'){Import-Module -Name $Manifest -ErrorAction Stop}
    $watch.Stop()
    $allocatedDelta=[GC]::GetTotalAllocatedBytes($false)-$allocated
    $managedDelta=[GC]::GetTotalMemory($false)-$managed
    $process.Refresh()
    $cpuDelta=$process.TotalProcessorTime.TotalMilliseconds-$cpu
    $workingDelta=$process.WorkingSet64-$working;$privateDelta=$process.PrivateMemorySize64-$private
    $module=Get-Module FrenchExDev2.QuietCli.Core.PoSh
    $loadedPath=$null;$engineStarted=$false
    if($Mode -eq 'Import'){
        $autoloaded=@(Get-Module Microsoft.PowerShell.Management,Microsoft.PowerShell.Utility)
        if($autoloaded.Count){throw 'CoreImportAutoloadedCmdletModules'}
        $expected=[IO.Path]::ChangeExtension([IO.Path]::GetFullPath($Manifest),'.psm1')
        if(!$module -or $module.Path -cne $expected){throw 'UnexpectedImportedCorePath'}
        if((Get-Alias quiet).ResolvedCommand.Module.Path -cne $expected){throw 'UnexpectedImportedQuietAlias'}
        $loadedPath=$module.Path
        $engineStarted=$null -ne [FrenchExDev2.QuietCli.QuietSession]::Engine
        if($engineStarted){throw 'ImportStartedEngine'}
    }elseif($module){throw 'BaselineLoadedCore'}
    [pscustomobject]@{
        Mode=$Mode;ProcessId=$PID;PowerShellVersion=$PSVersionTable.PSVersion.ToString()
        Runtime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription
        RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier
        Executable=(Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'}))
        ModulePath=$loadedPath;EngineStarted=$engineStarted;ElapsedMs=$watch.Elapsed.TotalMilliseconds
        CpuMs=$cpuDelta;AllocatedBytes=$allocatedDelta;ManagedBytesDelta=$managedDelta
        WorkingSetBytesDelta=$workingDelta;PrivateBytesDelta=$privateDelta
    }|ConvertTo-Json -Compress
}finally{$process.Dispose()}
