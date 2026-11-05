# Objectif : Exécuter les suites dans un conteneur Podman détenu et conserver les rapports sans capture métier.
#requires -Version 7.6
<#
.SYNOPSIS
Stages explicit sources and built artifacts into a private, networkless container.
.PARAMETER WorkspaceRoot
QuietCli2 root.
.PARAMETER RunDirectory
Dedicated host report directory.
.PARAMETER Image
Already prepared platform image; never pulled implicitly.
.PARAMETER Platform
Declared platform label, verified by the guest report.
.PARAMETER ExpectedRuntimeIdentifier
Required architecture and libc family in the actual guest and engine.
.PARAMETER Suite
Companion scope selected by the workflow.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[Parameter(Mandatory)][string]$Image,[Parameter(Mandatory)][string]$Platform,[string]$ExpectedRuntimeIdentifier,[ValidateSet('Core','Git','All')][string]$Suite='All')
$ErrorActionPreference='Stop';. (Join-Path $PSScriptRoot 'Common.ps1')
$owner=[guid]::NewGuid().ToString('N');$name='quietcli2-'+$owner.Substring(0,12)
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh + FrenchExDev2.QuietCli.Git.PoSh';Task='Tests Podman';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh');Platform=$Platform;State='Preparing';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');ProcessId=$PID;ContainerId=$name;Passed=$null;Failed=$null;Case='Staging explicit source files';FinishedUtc=$null;Error=$null;Image=$Image;Owner=$owner}
$status=Join-Path $RunDirectory 'status.json';Write-WorkspaceJson $status $state
$created=$false
try{
    $stage=Join-Path $RunDirectory 'workspace';[void][IO.Directory]::CreateDirectory($stage)
    foreach($directory in @('scripts','FrenchExDev2.QuietCli.Core.PoSh','FrenchExDev2.QuietCli.Core.Tests.PoSh','FrenchExDev2.QuietCli.Git.PoSh','FrenchExDev2.QuietCli.Git.Tests.PoSh')){
        $source=Join-Path $WorkspaceRoot $directory
        foreach($file in Get-ChildItem -LiteralPath $source -Recurse -File -Force){
            $relative=[IO.Path]::GetRelativePath($source,$file.FullName)
            if($relative -match '(^|[\\/])(\.git|bin|obj|artifacts)[\\/]'){continue}
            $destination=Join-Path (Join-Path $stage $directory) $relative
            [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
            Copy-Item -LiteralPath $file.FullName -Destination $destination
        }
    }
    foreach($file in @('global.json','repositories.lock.json')){if(Test-Path -LiteralPath (Join-Path $WorkspaceRoot $file)){Copy-Item -LiteralPath (Join-Path $WorkspaceRoot $file) -Destination $stage}}
    Write-WorkspaceJson (Join-Path $stage 'transport-origin.json') (Get-QuietWorkspaceIdentity $WorkspaceRoot -IncludeBinaries)
    $imageState=@{Id=$null}
    $inspect=pump -AsObject -TimeoutSeconds 20 -State $imageState -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){$s.Id=$e.Text.Trim()}} -Complete {param($s)$s.Id} podman image inspect --format '{{.Id}}' $Image
    if($inspect.Outcome -ne 'Success' -or $imageState.Id -notmatch '^(sha256:)?[a-f0-9]{64}$'){throw 'PreparedImageIdentityUnavailable'}
    $state.ImageId=$imageState.Id
    $guestArguments=@('-File','/workspace/scripts/Invoke-WorkspaceCi.ps1','-WorkspaceRoot','/workspace','-Headless','-SkipBuild','-RunDirectory','/workspace/artifacts/tests/container-run')
    if($ExpectedRuntimeIdentifier){$guestArguments+=@('-ExpectedRuntimeIdentifier',$ExpectedRuntimeIdentifier)}
    $guestArguments+=@('-Suite',$Suite)
    $null=Invoke-WorkspaceNative podman (@('create','--pull=never','--name',$name,'--label',('org.frenchexdev.quietcli2.owner='+$owner),'--network','none','--entrypoint','pwsh',$imageState.Id)+$guestArguments) $WorkspaceRoot -TimeoutSeconds 30
    $created=$true
    $null=Invoke-WorkspaceNative podman @('cp',$stage,($name+':/workspace')) $WorkspaceRoot -TimeoutSeconds 90
    $state.State='Running';$state.Case='Container running; elapsed time is a heartbeat, test counters not yet available';Write-WorkspaceJson $status $state
    $null=Invoke-WorkspaceNative podman @('start',$name) $WorkspaceRoot -TimeoutSeconds 30
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds(360)
    do{
        if([DateTimeOffset]::UtcNow -gt $deadline){throw [TimeoutException]::new('GuestTestDeadlineExceeded')}
        $progressPath=Join-Path $RunDirectory guest-progress.json
        $observation=@{Lines=0}
        $progress=pump -AsObject -TimeoutSeconds 15 -State $observation -OnOutput {param($e,$s)$s.Lines++} -Complete {param($s)$s.Lines} podman cp ($name+':/workspace/artifacts/tests/container-run/status.json') $progressPath
        if($progress.Outcome -eq 'Success'){
            $guest=Get-Content $progressPath -Encoding utf8 -Raw|ConvertFrom-Json
            $state.Passed=$guest.Passed;$state.Failed=$guest.Failed;$state.Case=$guest.Case;$state.GuestProcessId=$guest.ProcessId
            Write-WorkspaceJson $status $state
            if($guest.State -in @('Success','Failed','Crash','Timeout','Cancelled')){break}
        }
        $containerState=@{Value=''}
        $inspection=pump -AsObject -TimeoutSeconds 15 -State $containerState -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){$s.Value=$e.Text.Trim()}} -Complete {param($s)$s.Value} podman inspect --format '{{.State.Status}}' $name
        if($inspection.Outcome -ne 'Success' -or $containerState.Value -in @('exited','stopped')){break}
        [void][Threading.Tasks.Task]::Delay(2000).GetAwaiter().GetResult()
    }while($true)
    $null=Invoke-WorkspaceNative podman @('cp',($name+':/workspace/artifacts/tests/container-run'),(Join-Path $RunDirectory 'guest')) $WorkspaceRoot -TimeoutSeconds 60
    $summary=Get-Content -LiteralPath (Join-Path $RunDirectory 'guest/summary.json') -Encoding utf8 -Raw|ConvertFrom-Json
    if($ExpectedRuntimeIdentifier -and $summary.State.Platform -cne $ExpectedRuntimeIdentifier){throw 'GuestArchitectureMismatch'}
    $expected=if($Platform -eq 'alpine'){'^linux-musl-(x64|arm64)$'}else{'^linux-(x64|arm64)$'}
    if($summary.State.Platform -cnotmatch $expected -or $summary.EngineIdentity -and $summary.EngineIdentity.Engine.RuntimeIdentifier -cne $summary.State.Platform){throw 'GuestRuntimeDoesNotMatchRequestedPlatform'}
    $state.GuestIdentity=@{HostRuntime=$summary.HostRuntime;OSArchitecture=$summary.OSArchitecture;ProcessArchitecture=$summary.ProcessArchitecture;OSDescription=$summary.OSDescription;MachineName=$summary.MachineName;Engine=$summary.EngineIdentity.Engine}
    $state.Platform=$summary.State.Platform;$state.Passed=$summary.State.Passed;$state.Failed=$summary.State.Failed;$state.State=$summary.State.State;$state.Error=$summary.State.Error
    $state.Case='Guest terminal report retained'
}catch{$state.State='Crash';$state.Error=$_.ToString()}
finally{
    $state.Cleanup='NotCreated'
    if($created){try{$null=Invoke-WorkspaceNative podman @('rm','--force',$name) $WorkspaceRoot -TimeoutSeconds 20;$state.Cleanup='RemovedOwnedContainer'}catch{$state.Cleanup='Unconfirmed: owned container '+$name}}
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state}
    Write-WorkspaceJson $status $state
}
if($state.State -ne 'Success'){exit 1}
