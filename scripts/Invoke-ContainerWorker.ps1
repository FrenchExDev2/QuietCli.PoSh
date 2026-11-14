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
.PARAMETER Profiler
Enables a separate pinned PowerShell and CLR profiling pass, outside benchmark samples.
.PARAMETER ProfilerModulePath
Explicit Profiler 4.3.0 manifest; the launcher prepares a private cache when omitted.
.PARAMETER ClrProfilerPath
Explicit pinned dotnet-trace DLL.
.PARAMETER SkipTty
Excludes native TTY/PTY execution from this run; local runs include it by default.
.PARAMETER Suite
Companion scope or native C mutation campaign selected by the workflow.
.PARAMETER ContainerRuntime
Explicit selection overrides the checkout dotenv key; absent configuration uses Podman-first application discovery on Windows and Linux.
.PARAMETER GitHubActions
Runs the direct GitHub entry point inside the fallback container, without a nested local launcher.
.PARAMETER TimeoutSeconds
Explicit guest execution deadline, independent of the caller's job deadline.
.PARAMETER MaxConcurrency
Maximum number of internal test workers used by parallel-safe guest campaigns.
.PARAMETER Case
Development-only Core case wildcard; unavailable for the unfiltered GitHub entry point.
#>
[CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[Parameter(Mandatory)][string]$Image,[Parameter(Mandatory)][string]$Platform,[string]$ExpectedRuntimeIdentifier,[switch]$SkipTty,[switch]$Profiler,[string]$ProfilerModulePath,[string]$ClrProfilerPath,[AllowEmptyString()][ValidateSet('','podman','docker')][string]$ContainerRuntime,[switch]$GitHubActions,[ValidateRange(1,7200)][int]$TimeoutSeconds=360,[ValidateRange(1,32)][int]$MaxConcurrency=[Math]::Min(4,[Math]::Max(1,[Environment]::ProcessorCount)),[string]$Case)
dynamicparam {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
    $selectedRoot=if($PSBoundParameters.ContainsKey('WorkspaceRoot')){$PSBoundParameters['WorkspaceRoot']}else{Split-Path $PSScriptRoot -Parent}
    New-QuietWorkspaceSuiteParameter -WorkspaceRoot $selectedRoot -Scope Container
}
end {
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Invoke-ContainerWorker')){return}
$Suite=if($PSBoundParameters.ContainsKey('Suite')){[string]$PSBoundParameters['Suite']}else{'All'}
if($Case -and ($Suite -ne 'Core' -or $GitHubActions)){throw 'ContainerCaseRequiresLocalCoreSuite'}
$ErrorActionPreference='Stop';Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/ContainerInputs.psm1')) -DisableNameChecking -ErrorAction Stop
$ContainerRuntime=Resolve-QuietVirtEngine -ContainerRuntime $ContainerRuntime -WorkspaceRoot $WorkspaceRoot
$owner=[guid]::NewGuid().ToString('N');$name='quietcli2-'+$owner.Substring(0,12)
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh + FrenchExDev2.QuietCli.Git.PoSh';Task='Tests Podman';Workspace=$WorkspaceRoot;ProjectDirectory=([IO.Path]::Combine($WorkspaceRoot,'FrenchExDev2.QuietCli.Core.PoSh'));Platform=$Platform;State='Preparing';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');ProcessId=$PID;ContainerId=$name;Passed=$null;Failed=$null;Case='Staging explicit source files';FinishedUtc=$null;Error=$null;Image=$Image;Owner=$owner}
$state.Task='Tests '+$ContainerRuntime;$state.ContainerRuntime=$ContainerRuntime
$status=[IO.Path]::Combine($RunDirectory,'status.json')
$companionSelection=@(Get-QuietWorkspaceTestSuites $WorkspaceRoot | Where-Object {$Suite -eq 'All' -or $_.Name -eq $Suite})
if($companionSelection.Count){$state.Project=$companionSelection.Project -join ' + ';$state.ProjectDirectory=$companionSelection.ProjectDirectory -join ' | '}
if($Suite -eq 'Import'){$state.Project='FrenchExDev2.QuietCli.Core.PoSh';$state.Task='Core import cost in fresh pwsh sessions'}
if($Suite -eq 'Mutation'){$state.Project='FrenchExDev2.QuietCli.Core.PoSh';$state.Task='PTY properties, fuzzing and mutation'}
Write-WorkspaceJson $status $state
$created=$false
$guestSuites=@()
try{
    $stage=[IO.Path]::Combine($RunDirectory,'workspace');[void][IO.Directory]::CreateDirectory($stage)
    Copy-QuietContainerInputs -WorkspaceRoot $WorkspaceRoot -Destination $stage -NativeOnly:($Suite -eq 'Mutation') -ContainerRuntime $ContainerRuntime -Confirm:$false
    if($Suite -eq 'Mutation'){
        [void][IO.Directory]::CreateDirectory(([IO.Path]::Combine($stage,'scripts')))
        foreach($file in @('lib/ReportPaths.psm1','lib/Ci.Process.psm1','lib/Common.psm1','lib/EnvFile.psm1','lib/SourceIdentity.psm1','lib/WorkspaceProjects.psm1','lib/RuntimeTargets.psm1','lib/Assert-PtyQualification.psm1','Watch-Tests.ps1','lib/Monitor.Time.psm1','lib/ReportStreaming.psm1')){Copy-Item -LiteralPath ([IO.Path]::Combine($PSScriptRoot,$file)) -Destination ([IO.Path]::Combine($stage,('scripts/'+$file)))}
        $productFiles=@(Get-ChildItem $stage -Recurse -File|Where-Object Extension -In @('.dll','.csproj','.psd1','.psm1'))
        if($productFiles.Count){throw 'NativeStageMustNotContainProductBuildsOrModules'}
        Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'bootstrap.json')) @{Mode='Direct CI processes';ProductBuildFiles=0;NativeSourceSHA256=(Get-FileHash ([IO.Path]::Combine($stage,'FrenchExDev2.QuietCli.Core.PoSh/native/quietcli-pty.c')) -Algorithm SHA256).Hash}
    }else{
        foreach($file in @('global.json','Directory.Packages.props','repositories.lock.json')){if(Test-Path -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,$file))){Copy-Item -LiteralPath ([IO.Path]::Combine($WorkspaceRoot,$file)) -Destination $stage}}
        Write-WorkspaceJson ([IO.Path]::Combine($stage,'transport-origin.json')) (Get-QuietWorkspaceIdentity $WorkspaceRoot -IncludeBinaries)
    }
    $imageState=@{Id=$null}
    $inspect=Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('image','inspect','--format','{{.Id}}',$Image) -TimeoutSeconds 20 -State $imageState -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){$s.Id=$e.Text.Trim()}}
    if($inspect.Outcome -ne 'Success' -or $imageState.Id -notmatch '^(sha256:)?[a-f0-9]{64}$'){throw 'PreparedImageIdentityUnavailable'}
    $state.ImageId=$imageState.Id
    Write-Host ('CI container image: '+(@{Requested=$Image;ImageId=$imageState.Id;ExpectedRuntimeIdentifier=$ExpectedRuntimeIdentifier;Container=$name}|ConvertTo-Json -Compress))
    $guestArguments=if($Suite -eq 'Mutation'){
        @('-File','/workspace/FrenchExDev2.QuietCli.Core.Tests.PoSh/native-tests/Probe-Independent.ps1','-WorkspaceRoot','/workspace','-RunDirectory','/workspace/artifacts/tests/container-run')
    }else{@('-File','/workspace/scripts/Invoke-WorkspaceCi.ps1','-WorkspaceRoot','/workspace','-Headless','-SkipBuild','-RunDirectory','/workspace/artifacts/tests/container-run')}
    if($GitHubActions){$guestArguments=@('-File','/workspace/scripts/Invoke-GitHubCi.ps1','-WorkspaceRoot','/workspace','-SkipBuild','-RunDirectory','/workspace/artifacts/tests/container-run')}
    if($ExpectedRuntimeIdentifier){$guestArguments+=@('-ExpectedRuntimeIdentifier',$ExpectedRuntimeIdentifier)}
    if($Suite -ne 'Mutation'){$guestArguments+=@('-MaxConcurrency',$MaxConcurrency)}
    if($SkipTty){if($Suite -eq 'Mutation'){throw 'TtyMutationCannotRunWithSkipTty'};$guestArguments+='-SkipTty'}
    if($Suite -ne 'Mutation'){$guestArguments+=@('-Suite',$Suite)}
    if($Case){$guestArguments+=@('-Case',$Case)}
    if($Profiler){
        $toolRoot=[IO.Path]::Combine($stage,'.profilers')
        [void][IO.Directory]::CreateDirectory($toolRoot)
        Copy-Item -LiteralPath (Split-Path $ProfilerModulePath -Parent) -Destination ([IO.Path]::Combine($toolRoot,'Profiler')) -Recurse
        Copy-Item -LiteralPath (Split-Path $ClrProfilerPath -Parent) -Destination ([IO.Path]::Combine($toolRoot,'clr')) -Recurse
        $guestArguments+=@('-Profiler','-ProfilerModulePath','/workspace/.profilers/Profiler/Profiler.psd1','-ClrProfilerPath','/workspace/.profilers/clr/dotnet-trace.dll')
        $receipt=[IO.Path]::Combine((Split-Path (Split-Path $ProfilerModulePath -Parent) -Parent),'tool-receipt.json')
        if(Test-Path $receipt){Copy-Item -LiteralPath $receipt -Destination ([IO.Path]::Combine($RunDirectory,'tool-receipt.json'))}
    }
    $memoryLimits=if($Suite -eq 'Mutation'){@('--memory','1g','--memory-swap','1g')}else{@()}
    # Alpine's framework-dependent PowerShell uses the distribution .NET 10 runtime; the SDK has its own .NET 11 root.
    $runtimeEnvironment=if($Platform -eq 'alpine'){@('--env','DOTNET_ROOT=/opt/pwsh-runtime')}else{@()}
    if($GitHubActions){$runtimeEnvironment+=@('--env','GITHUB_ACTIONS=true')}
    if($Suite -ne 'Mutation'){$runtimeEnvironment+=@('--env','NUGET_PACKAGES=/workspace/artifacts/nuget-cache')}
    $null=Invoke-WorkspaceNative $ContainerRuntime (@('create','--pull=never','--name',$name,'--label',('org.frenchexdev.quietcli2.owner='+$owner),'--network','none')+$memoryLimits+$runtimeEnvironment+@('--entrypoint','pwsh',$imageState.Id)+$guestArguments) $WorkspaceRoot -TimeoutSeconds 30
    $created=$true
    $null=Invoke-WorkspaceNative $ContainerRuntime @('cp',($stage.Replace('\','/')+'/.'),($name+':/workspace')) $WorkspaceRoot -TimeoutSeconds 90
    $state.State='Running';$state.Case='Container running; elapsed time is a heartbeat, test counters not yet available';Write-WorkspaceJson $status $state
    $null=Invoke-WorkspaceNative $ContainerRuntime @('start',$name) $WorkspaceRoot -TimeoutSeconds 30
    $deadline=[DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
    do{
        if([DateTimeOffset]::UtcNow -gt $deadline){throw [TimeoutException]::new('GuestTestDeadlineExceeded')}
        $progressPath=[IO.Path]::Combine($RunDirectory,'guest-progress.json')
        $observation=@{Lines=0}
        $progress=Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('cp',($name+':/workspace/artifacts/tests/container-run/status.json'),$progressPath) -TimeoutSeconds 15 -State $observation -OnOutput {param($e,$s)$s.Lines++}
        if($progress.Outcome -eq 'Success'){
            $guest=Get-Content $progressPath -Encoding utf8 -Raw|ConvertFrom-Json
            $state.Passed=$guest.Passed;$state.Failed=$guest.Failed;$state.Case=$guest.Case;$state.GuestProcessId=$guest.ProcessId
            Write-WorkspaceJson $status $state
            # A report is not sufficient: the guest process must also reach a terminal state.
        }
        $containerState=@{Value=''}
        $inspection=Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('inspect','--format','{{.State.Status}}',$name) -TimeoutSeconds 15 -State $containerState -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){$s.Value=$e.Text.Trim()}}
        if($inspection.Outcome -ne 'Success' -or $containerState.Value -in @('exited','stopped')){break}
        [void][Threading.Tasks.Task]::Delay(2000).GetAwaiter().GetResult()
    }while($true)
    $null=Invoke-WorkspaceNative $ContainerRuntime @('cp',($name+':/workspace/artifacts/tests/container-run'),([IO.Path]::Combine($RunDirectory,'guest'))) $WorkspaceRoot -TimeoutSeconds $TimeoutSeconds
    $summary=Get-Content -LiteralPath ([IO.Path]::Combine($RunDirectory,'guest/summary.json')) -Encoding utf8 -Raw|ConvertFrom-Json
    if($summary.PSObject.Properties['Suites']){$guestSuites=@($summary.Suites)}
    $exit=@{Value=''}
    $exitInspection=Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('inspect','--format','{{.State.ExitCode}}',$name) -TimeoutSeconds 15 -State $exit -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){$s.Value=$e.Text.Trim()}}
    if($exitInspection.Outcome -ne 'Success' -or $exit.Value -notmatch '^-?\d+$'){throw 'GuestExitCodeUnconfirmed'}
    $state.GuestExitCode=[int]$exit.Value
    if($summary.State.State -eq 'Success' -and $state.GuestExitCode -ne 0){throw 'GuestExitedNonzeroAfterSuccessReport'}
    $engineIdentity=if($Suite -eq 'Mutation'){$null}else{$summary.EngineIdentity}
    if($ExpectedRuntimeIdentifier -and $summary.State.Platform -cne $ExpectedRuntimeIdentifier){throw 'GuestArchitectureMismatch'}
    $expected=if($Platform -eq 'alpine'){'^linux-musl-(x64|arm64)$'}else{'^linux-(x64|arm64)$'}
    if($summary.State.Platform -cnotmatch $expected -or $engineIdentity -and $engineIdentity.Engine.RuntimeIdentifier -cne $summary.State.Platform){throw 'GuestRuntimeDoesNotMatchRequestedPlatform'}
    $state.GuestIdentity=@{HostRuntime=$summary.HostRuntime;OSArchitecture=$summary.OSArchitecture;ProcessArchitecture=$summary.ProcessArchitecture;OSDescription=$summary.OSDescription;MachineName=$summary.MachineName;Engine=$(if($engineIdentity){$engineIdentity.Engine}else{$null})}
    $state.Platform=$summary.State.Platform;$state.Passed=$summary.State.Passed;$state.Failed=$summary.State.Failed;$state.State=$summary.State.State;$state.Error=$summary.State.Error
    if($Suite -eq 'Mutation'){
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Assert-PtyQualification.psm1')) -DisableNameChecking -ErrorAction Stop
        Assert-PtyQualification $summary
        $independence=Get-Content ([IO.Path]::Combine($RunDirectory,'guest/independence.json')) -Raw -Encoding utf8|ConvertFrom-Json
        if($independence.ProductBuildFiles -ne 0 -or $independence.LoadedProductModules -ne 0 -or $independence.ForbiddenAICommandCalls -ne 0){throw 'NativeIndependenceUnconfirmed'}
        $state.Independence=$independence
        $state.Baseline=$summary.Baseline;$state.Mutation=$summary.Mutation;$state.Fuzz=$summary.Fuzz
    }
    $state.Case='Guest terminal report retained'
}catch{
    $state.State='Crash';$state.Error=$_.ToString()
}
finally{
    if($created -and $state.State -ne 'Success'){
        $diagnostics=@{Lines=[Collections.Generic.Queue[object]]::new()}
        try{
            $logs=Invoke-CiProcess -FilePath $ContainerRuntime -ArgumentList @('logs',$name) -TimeoutSeconds 20 -State $diagnostics -OnOutput {param($e,$s)if($s.Lines.Count -ge 80){$null=$s.Lines.Dequeue()};$s.Lines.Enqueue(@{Stream=$e.Stream;Text=$e.Text})}
            Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'guest-diagnostics.json')) @{Outcome=$logs.Outcome;ExitCode=$logs.ExitCode;Lines=@($diagnostics.Lines)}
        }catch{Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'guest-diagnostics.json')) @{Outcome='Unavailable';Error=$_.ToString()}}
    }
    $state.Cleanup='NotCreated'
    if($created){try{$null=Invoke-WorkspaceNative $ContainerRuntime @('rm','--force',$name) $WorkspaceRoot -TimeoutSeconds 20;$state.Cleanup='RemovedOwnedContainer'}catch{$state.Cleanup='Unconfirmed: owned container '+$name}}
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'summary.json')) @{State=$state;Suites=$guestSuites}
    Write-WorkspaceJson $status $state
}
if($state.State -ne 'Success'){exit 1}

}
