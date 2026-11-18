#requires -Version 7.6
<#
.SYNOPSIS
Measures inert import and first/warm short calls in one owned, fresh PowerShell process.
.PARAMETER Manifest
Exact built Core manifest.
.PARAMETER Executable
Absolute Git executable; only --version is invoked.
.PARAMETER ConfigurationDirectory
Owned configuration and SQLite directory, prepared by the parent campaign.
.PARAMETER MeasurePhases
Explicitly enables diagnostic timers, separate from ordinary timing samples.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$Manifest,[string]$Executable,[string]$ConfigurationDirectory,[switch]$MeasurePhases)
$ErrorActionPreference='Stop'
$utf8=[Text.UTF8Encoding]::new($false)
[Console]::InputEncoding=$utf8;[Console]::OutputEncoding=$utf8;$OutputEncoding=$utf8
if(!$PSCmdlet.ShouldProcess($ConfigurationDirectory,'Measure fresh-process import and native calls')){return}
if(Get-Module FrenchExDev2.QuietCli.Core.PoSh){throw 'ContaminatedStartupProbe'}
if([AppDomain]::CurrentDomain.GetAssemblies().GetName().Name -match '^QuietCli\.Engine$'){throw 'ContaminatedStartupAssembly'}
$env:QUIETCLI_CONFIG_DIRECTORY=$ConfigurationDirectory
$watch=[Diagnostics.Stopwatch]::StartNew()
Import-Module -Name $Manifest -ErrorAction Stop
$watch.Stop();$importMs=$watch.Elapsed.TotalMilliseconds
$expected=[IO.Path]::ChangeExtension([IO.Path]::GetFullPath($Manifest),'.psm1')
if((Get-Module FrenchExDev2.QuietCli.Core.PoSh).Path -cne $expected -or $null -ne [FrenchExDev2.QuietCli.QuietSession]::Engine){throw 'StartupImportIdentityMismatch'}
$samples=[Collections.Generic.List[object]]::new()
try{
    foreach($iteration in 0..3){
        $parameters=@{AsObject=$true;Output={param($event,$runtime)};FilePath=$Executable;ArgumentList=@('--version')}
        if($MeasurePhases){$parameters.MeasurePhases=$true}
        $watch.Restart();$result=quiet @parameters;$watch.Stop()
        if($result.Outcome -ne 'Success' -or !$result.Completeness.Source -or !$result.Completeness.Analysis -or $result.Measurement.StorageError){throw 'StartupCallFailed'}
        $row=[ordered]@{Stage=$(if($iteration -eq 0){'FirstCall'}else{'WarmCall'});Iteration=$iteration;InvocationMs=$watch.Elapsed.TotalMilliseconds;ExecutionMs=$result.Execution.ElapsedMs;NativeMs=$result.Execution.Native.ElapsedMs;ResultConstructionMs=$null;MetadataProjectionMs=$null;SaveRoundTripMs=$null;QueueWaitMs=$null;WriteGateWaitMs=$null;ValidationMs=$null;WriterPreparationMs=$null;SqliteWriteMs=$null;WriterAlreadyPrepared=$null}
        if($MeasurePhases){
            $phases=$result.Measurement.Phases
            foreach($name in @('ResultConstructionMs','MetadataProjectionMs','SaveRoundTripMs')){$row[$name]=$phases[$name]}
            if($null -ne $phases.Storage){
                foreach($name in @('QueueWaitMs','WriteGateWaitMs','ValidationMs','WriterPreparationMs','SqliteWriteMs','WriterAlreadyPrepared')){$row[$name]=$phases.Storage.$name}
            }
        }
        $samples.Add([pscustomobject]$row)
    }
    $identity=Get-QuietEngine
    [pscustomobject]@{ProcessId=$PID;PowerShellVersion=$PSVersionTable.PSVersion.ToString();Runtime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;EngineMode=$identity.Mode;MeasurePhases=[bool]$MeasurePhases;DatabaseCreated=[IO.File]::Exists([IO.Path]::Combine($ConfigurationDirectory,'measurements.sqlite'));ImportMs=$importMs;Calls=$samples.ToArray()}|ConvertTo-Json -Depth 8 -Compress
}finally{Stop-QuietEngine}
