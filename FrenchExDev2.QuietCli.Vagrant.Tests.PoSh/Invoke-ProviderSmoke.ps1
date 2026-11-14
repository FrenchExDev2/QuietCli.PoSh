#requires -Version 7.6
<#
.SYNOPSIS
Checks real two-machine Vagrant behavior with an existing Docker-compatible engine and a visible monitor.
.DESCRIPTION
Copies the committed fixture into a private run directory. Uses an isolated Vagrant home, unique
container names and no plugins. Builds the fixture image, so network access may be needed. Never
installs tools or configures the engine. Destroy targets only the copied Vagrant environment;
downloaded base images and build caches are retained. This is opt-in development evidence, not release qualification.
.PARAMETER WorkspaceRoot
Selected QuietCli monorepo.
.PARAMETER RunDirectory
New external report directory, generated when omitted.
.PARAMETER Worker
Internal background entry point. Use the normal entry point to retain the visible monitor.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$RunDirectory,[switch]$Worker)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
if(!$Worker){
    if(!$IsWindows){throw 'Launch the visible provider smoke monitor from Windows.'}
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'vagrant-provider') ([guid]::NewGuid().ToString('N'))}
    if(Test-Path -LiteralPath $RunDirectory){throw 'ProviderSmokeRunExists'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixture') -Destination $RunDirectory -Recurse
    $runner=Join-Path $PSHOME 'pwsh.exe'
    $process=Start-Process $runner -WindowStyle Hidden -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $PSCommandPath),'-WorkspaceRoot',(ConvertTo-CiArgument $WorkspaceRoot),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory),'-Worker') -RedirectStandardOutput (Join-Path $RunDirectory 'worker.stdout.log') -RedirectStandardError (Join-Path $RunDirectory 'worker.stderr.log')
    $monitorPath=Join-Path $WorkspaceRoot 'scripts/Watch-Tests.ps1'
    $monitor=Start-Process $runner -WindowStyle Normal -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardError (Join-Path $RunDirectory 'monitor.stderr.log')
    'Monitor: pwsh -File '+(ConvertTo-CiArgument $monitorPath)+' -RunDirectory '+(ConvertTo-CiArgument $RunDirectory)
    $summary=Wait-WorkspaceWorker -Worker $process -Monitor $monitor -Runner $runner -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -TimeoutSeconds 1800
    [pscustomobject]@{State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;RunDirectory=$RunDirectory}
    if($summary.State.State -ne 'Success'){throw "Provider smoke failed: $RunDirectory"};return
}
$fixture=Join-Path $RunDirectory 'fixture'
$prefix='quietcli-'+[guid]::NewGuid().ToString('N').Substring(0,16)
$environment=@{QUIETCLI_VAGRANT_PREFIX=$prefix;VAGRANT_HOME=(Join-Path $RunDirectory 'vagrant-home');VAGRANT_CHECKPOINT_DISABLE='1';VAGRANT_DEFAULT_PROVIDER='docker'}
$state=@{Project='FrenchExDev2.QuietCli.Vagrant.PoSh';Task='Real Vagrant Docker-provider smoke';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Vagrant.PoSh');Platform='Windows x64 / Docker API';State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;ProcessId=$PID;Passed=0;Failed=0;Case='Readiness';Error=$null;ContainerId="$prefix-web + $prefix-db"}
$statusPath=Join-Path $RunDirectory 'status.json'
$cases=[Collections.Generic.List[object]]::new()
$observations=[Collections.Generic.List[object]]::new()
$cleanup=$null;$attempted=$false
Write-WorkspaceJson $statusPath $state
function Invoke-ProviderProbe {
    <# .SYNOPSIS
    Runs one native probe with explicit bounded diagnostics and no automatic output capture.
    .PARAMETER FilePath
    Tool selected by the probe.
    .PARAMETER Arguments
    Exact argument vector.
    #>
    param([string]$FilePath,[string[]]$Arguments)
    $buffer=[Text.StringBuilder]::new()
    $result=quiet -AsObject -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $fixture -Environment $environment -TimeoutSeconds 90 -Data $buffer -Output {param($e,$rt) if($rt.Data.Length -lt 12000){[void]$rt.Data.Append($e.Text)}} -Complete {param($rt) $rt.Data.ToString()}
    [void]$observations.Add(@{Tool=$FilePath;Arguments=$Arguments;Outcome=$result.Outcome;Execution=$result.Execution;Completeness=$result.Completeness;Error=$result.Error;DiagnosticTail=$buffer.ToString()})
    return $result
}
function Assert-ProviderCase {
    <# .SYNOPSIS
    Records an independently observable provider invariant and fails without hiding diagnostics.
    .PARAMETER Name
    Business invariant.
    .PARAMETER Condition
    Observed truth value.
    #>
    param([string]$Name,[bool]$Condition)
    [void]$cases.Add(@{Name=$Name;Passed=$Condition})
    if($Condition){$state.Passed++}else{$state.Failed++}
    Write-WorkspaceJson $statusPath $state
    if(!$Condition){throw "ProviderInvariantFailed: $Name"}
}
try{
    Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1') -ErrorAction Stop
    Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Vagrant.PoSh/FrenchExDev2.QuietCli.Vagrant.PoSh.psd1') -ErrorAction Stop
    Write-WorkspaceJson (Join-Path $RunDirectory 'inputs.json') @{Environment=$environment;Engine=(Get-QuietEngine);Sources=@(Get-ChildItem -LiteralPath $fixture -File | ForEach-Object {@{Name=$_.Name;SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})}
    $version=Invoke-ProviderProbe 'vagrant' @('--version')
    Assert-ProviderCase 'Vagrant version probe completed' ($version.Outcome -eq 'Success' -and $version.Data.Trim() -eq 'Vagrant 2.4.9')
    $docker=Invoke-ProviderProbe 'docker' @('info','--format','{{json .ServerVersion}}')
    Assert-ProviderCase 'Docker-compatible engine is reachable' ($docker.Outcome -eq 'Success')
    $validate=Invoke-ProviderProbe 'vagrant' @('validate')
    Assert-ProviderCase 'Committed two-machine fixture validates' ($validate.Outcome -eq 'Success')
    $vagrantfile=Join-Path $fixture 'Vagrantfile'
    $source=[IO.File]::ReadAllTextAsync($vagrantfile,[Text.UTF8Encoding]::new($false,$true)).GetAwaiter().GetResult()
    $random=[Random]::new(20261109)
    try{
        $state.Case='Fixture prefix properties and malformed values';Write-WorkspaceJson $statusPath $state
        $valid=@('a',('a'*56),('a-'+$random.Next()),('z'+$random.Next()+'-end'))
        foreach($value in $valid){
            $environment.QUIETCLI_VAGRANT_PREFIX=$value
            $check=Invoke-ProviderProbe 'vagrant' @('validate')
            Assert-ProviderCase ('Valid fixture prefix: '+$value) ($check.Outcome -eq 'Success')
        }
        foreach($value in @('Upper','../escape',('a'*57),'a/b',"a`n",'été')){
            $environment.QUIETCLI_VAGRANT_PREFIX=$value
            $check=Invoke-ProviderProbe 'vagrant' @('validate')
            Assert-ProviderCase ('Malformed fixture prefix rejected: '+$value.Replace("`n",'\\n')) ($check.Outcome -ne 'Success' -and $check.Data -match 'Invalid fixture prefix')
        }
        $anchor='raise "Invalid fixture prefix" unless prefix.match?(/\A[a-z][a-z0-9-]{0,55}\z/)'
        if(([regex]::Matches($source,[regex]::Escape($anchor))).Count -ne 1){throw 'FixtureMutationAnchorInvalid'}
        [IO.File]::WriteAllTextAsync($vagrantfile,$source.Replace($anchor,'# Prefix guard removed by isolated test mutation.'),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $environment.QUIETCLI_VAGRANT_PREFIX='Upper'
        $mutant=Invoke-ProviderProbe 'vagrant' @('validate')
        Assert-ProviderCase 'Fixture prefix guard mutant is detected by the malformed-value invariant' ($mutant.Outcome -eq 'Success')
    }finally{
        $environment.QUIETCLI_VAGRANT_PREFIX=$prefix
        [IO.File]::WriteAllTextAsync($vagrantfile,$source,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    }
    foreach($step in @(@{Name='up-no-provision';Args=@('up','--provider=docker','--no-provision','--no-parallel','--no-install-provider')},@{Name='provision';Args=@('provision')})){
        $state.Case=$step.Name;Write-WorkspaceJson $statusPath $state
        $seen=[Collections.Generic.List[object]]::new()
        $listener={param($event,$runtime) if($seen.Count -ge 5000){throw 'SmokeEventLimit'};[void]$seen.Add($event);$description=if($event.PSObject.Properties['Fields']){$event.Fields -join ' '}else{$event.Kind};$state.Case=$step.Name+': '+$seen.Count+' events | '+$description.Substring(0,[Math]::Min(120,$description.Length));Write-WorkspaceJson $statusPath $state}
        $attempted=$true
        $result=quiet -AsObject -CollectEvents -Ui -FilePath 'vagrant' -ArgumentList $step.Args -WorkingDirectory $fixture -Environment $environment -TimeoutSeconds 600 -Listeners $listener
        Write-WorkspaceJson (Join-Path $RunDirectory ($step.Name+'.json')) @{Outcome=$result.Outcome;Execution=$result.Execution;Completeness=$result.Completeness;Error=$result.Error;Data=$result.Data;Events=$seen.ToArray()}
        Assert-ProviderCase ($step.Name+' completed without source/analysis loss') ($result.Outcome -eq 'Success' -and $result.Completeness.Source -and $result.Completeness.Analysis -and !$result.Error.Count)
        $ordered=$seen.Count -eq $result.Events.Count -and $seen.Count -gt 0
        for($index=0;$ordered -and $index -lt $seen.Count;$index++){$ordered=[object]::ReferenceEquals($seen[$index],$result.Events[$index])}
        Assert-ProviderCase ($step.Name+' preserves listener/collected event order') $ordered
        $machines=@($seen | ForEach-Object {if($_.PSObject.Properties['Machine'] -and $_.Machine){$_.Machine}} | Select-Object -Unique)
        Assert-ProviderCase ($step.Name+' observes both machines') ('web' -in $machines -and 'db' -in $machines)
        $starts=@($seen | Where-Object {$_.PSObject.Properties['Kind'] -and $_.Kind -eq 'ProvisionerStarted'})
        if($step.Name -eq 'up-no-provision'){
            Assert-ProviderCase 'No-provision emits no provisioner-start event' ($starts.Count -eq 0)
        }else{
            foreach($machine in 'web','db'){
                Assert-ProviderCase ($machine+' shell provisioner is observed') (@($starts | Where-Object Machine -eq $machine).Count -ge 1)
                Assert-ProviderCase ($machine+' shell output contains the fixture sentinel') (@($seen | Where-Object {$_.Machine -eq $machine -and $_.PSObject.Properties['Fields'] -and ($_.Fields -join ' ') -match "provisioning $machine"}).Count -ge 1)
            }
        }
    }
    $state.State='Success'
}catch{
    $state.State='Failed';$state.Error=$_.Exception.Message
    if(!$state.Failed){$state.Failed++}
}finally{
    if($attempted){
        $state.Case='Destroy owned copied fixture';Write-WorkspaceJson $statusPath $state
        try{
            if($state.State -ne 'Success'){
                foreach($machine in 'web','db'){$null=Invoke-ProviderProbe 'docker' @('logs','--tail','30',"$prefix-$machine")}
            }
            $cleanup=Invoke-ProviderProbe 'vagrant' @('destroy','--force','--no-parallel')
            if($cleanup.Outcome -ne 'Success'){$state.State='Failed';$state.Failed++;$state.Error+='; Owned fixture cleanup failed'}
            $remaining=Invoke-ProviderProbe 'docker' @('ps','--all','--filter',"name=$prefix",'--format','{{.Names}}')
            if($remaining.Outcome -ne 'Success' -or $remaining.Data.Trim()){$state.State='Failed';$state.Failed++;$state.Error+='; Owned container removal not confirmed'}
        }catch{$state.State='Failed';$state.Failed++;$state.Error+='; Cleanup: '+$_.Exception.Message}
    }
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state;Cases=$cases.ToArray();Probes=$observations.ToArray();Cleanup=if($cleanup){$cleanup.Outcome}else{'NotNeeded'};Retained='Reports, fixture state, downloaded base images and build caches';Qualification='Partial'}
    Write-WorkspaceJson $statusPath $state
}
if($state.State -ne 'Success'){throw "Provider smoke failed: $RunDirectory"}
