#requires -Version 7.6
<#
.SYNOPSIS
Diagnoses a prepared Linux image without pulling, rebuilding, installing or changing RID guards.
.DESCRIPTION
Runs default and explicit runtime-root controls in one uniquely labelled, networkless disposable container.
Only allowlisted identity/configuration fields and bounded failure diagnostics are saved. The immutable
image ID, source hashes, native asset hashes and cleanup result remain in the report. Success means
the diagnostic completed; inspect Diagnosis.Decision, which is never product qualification.
.PARAMETER Image
Existing local image reference; resolved once to its immutable ID.
.PARAMETER ExpectedRuntimeIdentifier
Portable Linux target from the workspace catalogue.
.PARAMETER RuntimeRoots
Explicit Linux .NET roots compared with the unchanged image default.
.PARAMETER ExpectedRuntimeMajor
Required CLR major for the selected PowerShell host, normally 10 for stable.
.PARAMETER WorkspaceRoot
Workspace supplying diagnostic scripts and verified native resources.
.PARAMETER RunDirectory
New report directory, generated under the shared temporary report root when omitted.
.PARAMETER Headless
CI-only launch without the local Windows monitoring window.
.PARAMETER Worker
Internal background entry point; use the normal launcher locally.
#>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Image,
    [Parameter(Mandatory)][ValidatePattern('^linux-(musl-)?(x64|arm64)$')][string]$ExpectedRuntimeIdentifier,
    [string[]]$RuntimeRoots=@('/usr/lib/dotnet','/usr/share/dotnet'),[ValidateRange(10,99)][int]$ExpectedRuntimeMajor=10,
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$RunDirectory,[switch]$Headless,[switch]$Worker)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Common.ps1')
Import-Module (Join-Path $PSScriptRoot 'lib/RuntimeDiagnosis.psm1')
if($ExpectedRuntimeIdentifier -cnotin @(Get-QuietRuntimeTargets $WorkspaceRoot).Rid){throw 'DiagnosticTargetNotDistributed'}
foreach($runtimeRoot in $RuntimeRoots){if($runtimeRoot -cnotmatch '^/[A-Za-z0-9_./-]+$' -or $runtimeRoot.Contains('..')){throw 'DiagnosticRuntimeRootInvalid'}}
if(!$Worker){
    if(!$Headless -and !$IsWindows){throw 'Launch locally from Windows for the visible diagnostic monitor.'}
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'runtime-diagnosis') ([guid]::NewGuid().ToString('N'))}
    if(Test-Path -LiteralPath $RunDirectory){throw 'RuntimeDiagnosisRunExists'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    Write-WorkspaceJson (Join-Path $RunDirectory 'request.json') @{Image=$Image;ExpectedRuntimeIdentifier=$ExpectedRuntimeIdentifier;RuntimeRoots=$RuntimeRoots;ExpectedRuntimeMajor=$ExpectedRuntimeMajor}
    $runner=Join-Path $PSHOME $(if($IsWindows){'pwsh.exe'}else{'pwsh'})
    $arguments=@('-File',(ConvertTo-CiArgument $PSCommandPath),'-WorkspaceRoot',(ConvertTo-CiArgument $WorkspaceRoot),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory),'-Image',(ConvertTo-CiArgument $Image),'-ExpectedRuntimeIdentifier',$ExpectedRuntimeIdentifier,'-Worker')
    $options=@{FilePath=$runner;ArgumentList=$arguments;PassThru=$true;RedirectStandardOutput=(Join-Path $RunDirectory 'worker.stdout.log');RedirectStandardError=(Join-Path $RunDirectory 'worker.stderr.log')}
    if($IsWindows){$options.WindowStyle='Hidden'}
    $process=Start-Process @options
    $monitor=$null
    if(!$Headless){$monitorPath=Join-Path $PSScriptRoot 'Watch-Tests.ps1';$monitor=Start-Process $runner -WindowStyle Normal -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardError (Join-Path $RunDirectory 'monitor.stderr.log');'Monitor: pwsh -File '+(ConvertTo-CiArgument $monitorPath)+' -RunDirectory '+(ConvertTo-CiArgument $RunDirectory)}
    $summary=Wait-WorkspaceWorker -Worker $process -Monitor $monitor -Runner $runner -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -TimeoutSeconds 600
    [pscustomobject]@{State=$summary.State.State;Decision=$summary.Diagnosis.Decision;RunDirectory=$RunDirectory;Cleanup=$summary.State.Cleanup}
    if($summary.State.State -ne 'Success'){throw "Runtime diagnosis incomplete: $RunDirectory"};return
}
$request=Get-Content -LiteralPath (Join-Path $RunDirectory 'request.json') -Raw -Encoding utf8|ConvertFrom-Json
$RuntimeRoots=@($request.RuntimeRoots);$ExpectedRuntimeMajor=$request.ExpectedRuntimeMajor
$owner=[guid]::NewGuid().ToString('N');$name='quietcli-runtime-'+$owner.Substring(0,12)
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='Container runtime and RID diagnosis';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh');Platform=$ExpectedRuntimeIdentifier;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;ProcessId=$PID;ContainerId=$name;Passed=$null;Failed=$null;Case='Inspect immutable image';Error=$null;Cleanup='NotCreated';Runs=@()}
$status=Join-Path $RunDirectory 'status.json'
$commands=[Collections.Generic.List[object]]::new();$observations=[Collections.Generic.List[object]]::new()
$created=$false;$imageIdentity=$null;$diagnosis=$null
Write-WorkspaceJson $status $state
function Invoke-DiagnosisProcess {
    <# .SYNOPSIS
    Runs one administrative command with explicit bounded diagnostics and preserves its exit state.
    .PARAMETER Arguments
    Exact Podman argument vector; never a string-built host shell command.
    #>
    param([string[]]$Arguments)
    $buffer=@{Lines=[Collections.Generic.List[string]]::new()}
    $result=Invoke-CiProcess -FilePath podman -ArgumentList $Arguments -TimeoutSeconds 60 -State $buffer -OnOutput {param($event,$data)if($data.Lines.Count -lt 20){$data.Lines.Add($event.Text.Substring(0,[Math]::Min(2000,$event.Text.Length)))}}
    $record=[pscustomobject]@{Arguments=$Arguments;Outcome=$result.Outcome;ExitCode=$result.ExitCode;ElapsedMs=$result.ElapsedMs;Diagnostics=$buffer.Lines.ToArray()}
    $commands.Add($record)
    return $record
}
try{
    $imageIdentity=[ordered]@{}
    foreach($field in 'Id','Architecture','Os'){
        $reference=if($field -eq 'Id'){$Image}else{$imageIdentity['Id']}
        $inspection=Invoke-DiagnosisProcess @('image','inspect','--format',('{{.'+$field+'}}'),$reference)
        if($inspection.Outcome -ne 'Success'){throw 'DiagnosticImageUnavailable'}
        $imageIdentity[$field]=($inspection.Diagnostics -join "`n").Trim()
        if($field -eq 'Id' -and $imageIdentity[$field] -cnotmatch '^(sha256:)?[a-f0-9]{64}$'){throw 'DiagnosticImageIdentityInvalid'}
    }
    if($imageIdentity.Id -cnotmatch '^(sha256:)?[a-f0-9]{64}$' -or $imageIdentity.Os -cne 'linux'){throw 'DiagnosticImageIdentityInvalid'}
    $stage=Join-Path $RunDirectory 'inputs';[void][IO.Directory]::CreateDirectory($stage)
    foreach($file in 'Probe-ContainerRuntime.ps1','Ci.Process.ps1','RuntimeTargets.ps1'){Copy-Item -LiteralPath (Join-Path $PSScriptRoot $file) -Destination $stage}
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'lib/RuntimeDiagnosis.psm1') -Destination $stage
    Import-Module (Join-Path $stage 'RuntimeDiagnosis.psm1') -Force
    $assets=Join-Path $stage 'assets';[void][IO.Directory]::CreateDirectory($assets)
    $inventory=@(foreach($target in Get-QuietRuntimeTargets $WorkspaceRoot|Where-Object Rid -Like 'linux-*'){
        $source=Join-Path $WorkspaceRoot ("FrenchExDev2.QuietCli.Core.PoSh/resources/runtime/runtimes/$($target.Rid)/native/libe_sqlite3.so")
        if(Test-Path -LiteralPath $source){$destination=Join-Path $assets $target.Rid;[void][IO.Directory]::CreateDirectory($destination);Copy-Item -LiteralPath $source -Destination $destination;@{Rid=$target.Rid;SHA256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash}}
    })
    Write-WorkspaceJson (Join-Path $assets 'assets.json') $inventory
    $bindings=@(foreach($relative in 'FrenchExDev2.QuietCli.Core.PoSh/engine/EngineSession.cs','FrenchExDev2.QuietCli.Core.PoSh/engine/TerminalBridge.cs','scripts/Invoke-TestWorker.ps1'){
        $path=Join-Path $WorkspaceRoot $relative
        @{Path=$relative;SHA256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;RelevantLines=@(Select-String -LiteralPath $path -Pattern 'RuntimeInformation.RuntimeIdentifier|HostRuntimeMismatch'|ForEach-Object {@{Line=$_.LineNumber;Text=$_.Line.Trim()}})}
    })
    Write-WorkspaceJson (Join-Path $RunDirectory 'inputs.json') @{Image=$imageIdentity;Assets=$inventory;SourceBindings=$bindings;Scripts=@(Get-ChildItem -LiteralPath $stage -File|ForEach-Object {@{Path=$_.Name;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})}
    $creation=Invoke-DiagnosisProcess @('create','--pull=never','--network=none','--name',$name,'--label',('org.frenchexdev.quietcli2.owner='+$owner),'--entrypoint','/bin/sh',$imageIdentity.Id,'-c','sleep 540')
    if($creation.Outcome -ne 'Success'){throw 'DiagnosticContainerCreateFailed'};$created=$true
    if((Invoke-DiagnosisProcess @('cp',($stage.Replace('\','/')+'/.'),($name+':/diagnostic'))).Outcome -ne 'Success'){throw 'DiagnosticStagingFailed'}
    if((Invoke-DiagnosisProcess @('start',$name)).Outcome -ne 'Success'){throw 'DiagnosticContainerStartFailed'}
    $variants=@(@{Name='Default';Root=$null})+@(for($index=0;$index -lt $RuntimeRoots.Count;$index++){@{Name=('Root'+$index);Root=$RuntimeRoots[$index]}})
    foreach($variant in $variants){
        $row=@{Platform='-';State='Running';Identity=($name+'/'+$variant.Name);StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null};$state.Runs+=,$row
        $state.Case='Probe '+$variant.Name+' '+$variant.Root;Write-WorkspaceJson $status $state
        $environment=if($variant.Root){@('--env',('DOTNET_ROOT='+$variant.Root),'--env',('DOTNET_ROOT_'+$(if($imageIdentity.Architecture -eq 'arm64'){'ARM64'}else{'X64'})+'='+$variant.Root))}else{@()}
        $guestPath='/diagnostic/'+$variant.Name+'.json'
        $execution=Invoke-DiagnosisProcess (@('exec')+$environment+@($name,'pwsh','-File','/diagnostic/Probe-ContainerRuntime.ps1','-OutputPath',$guestPath,'-AssetsRoot','/diagnostic/assets','-ExpectedRuntimeIdentifier',$ExpectedRuntimeIdentifier))
        $probe=$null
        $copy=Invoke-DiagnosisProcess @('cp',($name+':'+$guestPath),(Join-Path $RunDirectory ($variant.Name+'.json')))
        if($copy.Outcome -eq 'Success'){$probe=Get-Content -LiteralPath (Join-Path $RunDirectory ($variant.Name+'.json')) -Raw -Encoding utf8|ConvertFrom-Json}
        if($probe -and $probe.RuntimeIdentifier){$row.Platform=$probe.RuntimeIdentifier;$state.Platform=$probe.RuntimeIdentifier}
        $complete=$execution.Outcome -eq 'Success' -and $probe -and $probe.Phase -eq 'Complete'
        $observations.Add([pscustomobject]@{Name=$variant.Name;RuntimeRoot=$variant.Root;Outcome=if($complete){'Success'}else{'Failed'};Execution=$execution;Probe=$probe})
        $row.State=if($complete){'Success'}else{'Failed'};$row.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');Write-WorkspaceJson $status $state
    }
    $diagnosis=Get-QuietRuntimeDiagnosis -Image $imageIdentity -Observations $observations.ToArray() -ExpectedRuntimeIdentifier $ExpectedRuntimeIdentifier -ExpectedRuntimeMajor $ExpectedRuntimeMajor
    Write-WorkspaceJson (Join-Path $RunDirectory 'diagnosis.json') $diagnosis
    $state.State='Success';$state.Case=$diagnosis.Decision
}catch{$state.State='Crash';$state.Error=$_.ToString()}
finally{
    if($created){try{$removed=Invoke-DiagnosisProcess @('rm','--force',$name);$state.Cleanup=if($removed.Outcome -eq 'Success'){'RemovedOwnedContainer'}else{'Unconfirmed'};if($state.Cleanup -eq 'Unconfirmed'){$state.State='Failed';$state.Error='Owned diagnostic container cleanup failed'}}catch{$state.State='Failed';$state.Cleanup='Unconfirmed';$state.Error=$_.ToString()}}
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'commands.json') $commands.ToArray()
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state;Diagnosis=$diagnosis;Image=$imageIdentity;Observations=$observations.ToArray();Qualification='DiagnosticOnly'}
    Write-WorkspaceJson $status $state
}
if($state.State -ne 'Success'){exit 1}
