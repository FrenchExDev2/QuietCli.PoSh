#requires -Version 7.6
<#
.SYNOPSIS
Builds the declared Alpine image and verifies stable PowerShell, native assets and the pinned SDK with a visible monitor.
.DESCRIPTION
Builds locally without registry publication. Network access is required by the build. The image and
build caches are retained; runtime probes remove only their own containers. A remaining module RID
selection finding is recorded separately from image-bootstrap success.
.PARAMETER WorkspaceRoot
Selected QuietCli monorepo.
.PARAMETER RuntimeIdentifier
Alpine architecture to build on the matching native Podman backend.
.PARAMETER RunDirectory
New external evidence directory, generated when omitted.
.PARAMETER Worker
Internal background entry point. Use the normal launcher for local visible monitoring.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [ValidateSet('linux-musl-x64','linux-musl-arm64')][string]$RuntimeIdentifier='linux-musl-x64',[string]$RunDirectory,[switch]$Worker)
$ErrorActionPreference='Stop'
. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
if(!$Worker){
    if(!$IsWindows){throw 'Launch the visible Alpine smoke monitor from Windows.'}
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'alpine-image') ([guid]::NewGuid().ToString('N'))}
    if(Test-Path -LiteralPath $RunDirectory){throw 'AlpineSmokeRunExists'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $runner=Join-Path $PSHOME 'pwsh.exe'
    $process=Start-Process $runner -WindowStyle Hidden -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $PSCommandPath),'-WorkspaceRoot',(ConvertTo-CiArgument $WorkspaceRoot),'-RuntimeIdentifier',$RuntimeIdentifier,'-RunDirectory',(ConvertTo-CiArgument $RunDirectory),'-Worker') -RedirectStandardOutput (Join-Path $RunDirectory 'worker.stdout.log') -RedirectStandardError (Join-Path $RunDirectory 'worker.stderr.log')
    $monitorPath=Join-Path $WorkspaceRoot 'scripts/Watch-Tests.ps1'
    $monitor=Start-Process $runner -WindowStyle Normal -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardError (Join-Path $RunDirectory 'monitor.stderr.log')
    'Monitor: pwsh -File '+(ConvertTo-CiArgument $monitorPath)+' -RunDirectory '+(ConvertTo-CiArgument $RunDirectory)
    $summary=Wait-WorkspaceWorker -Worker $process -Monitor $monitor -Runner $runner -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -TimeoutSeconds 2400
    [pscustomobject]@{State=$summary.State.State;Passed=$summary.State.Passed;Failed=$summary.State.Failed;Image=$summary.Image.Image;RemainingDecision=$summary.Diagnosis.Decision;RunDirectory=$RunDirectory}
    if($summary.State.State -ne 'Success'){throw "Alpine image smoke failed: $RunDirectory"};return
}
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='Alpine image build and runtime smoke';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh');Platform=$RuntimeIdentifier;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;ProcessId=$PID;Passed=0;Failed=0;Case='Native backend preflight';Error=$null;Cleanup='NotCreated'}
$status=Join-Path $RunDirectory 'status.json';Write-WorkspaceJson $status $state
$receipt=$null;$diagnosis=$null;$sdk=$null;$backend=$null;$sdkName='quietcli-sdk-'+[guid]::NewGuid().ToString('N').Substring(0,12);$sdkAttempted=$false
$checks=[Collections.Generic.List[object]]::new()
function Invoke-AlpineSmokeNative {
    <# .SYNOPSIS
    Runs one explicit Podman control with bounded selected stdout and diagnostics.
    .PARAMETER Arguments
    Exact argument vector.
    #>
    param([string[]]$Arguments)
    $data=@{Stdout=[Collections.Generic.List[string]]::new();Stderr=[Collections.Generic.List[string]]::new()}
    $result=Invoke-CiProcess -FilePath podman -ArgumentList $Arguments -TimeoutSeconds 60 -State $data -OnOutput {param($event,$value)$list=if($event.Stream -eq 'stdout'){,$value.Stdout}else{,$value.Stderr};if($list.Count -lt 20){$list.Add($event.Text)}}
    [pscustomobject]@{Outcome=$result.Outcome;ExitCode=$result.ExitCode;Stdout=$data.Stdout.ToArray();Stderr=$data.Stderr.ToArray()}
}
function Assert-AlpineSmoke {
    <# .SYNOPSIS
    Saves an independently observable image requirement before stopping on a failure.
    .PARAMETER Name
    Requirement being checked.
    .PARAMETER Condition
    Observed condition.
    #>
    param([string]$Name,[bool]$Condition)
    $checks.Add(@{Name=$Name;Passed=$Condition})
    if($Condition){$state.Passed++}else{$state.Failed++}
    Write-WorkspaceJson $status $state
    if(!$Condition){throw ('AlpineSmokeInvariantFailed: '+$Name)}
}
try{
    $backend=Invoke-AlpineSmokeNative @('info','--format','{{.Host.OS}} {{.Host.Arch}}')
    Write-WorkspaceJson (Join-Path $RunDirectory 'backend.json') $backend
    $architecture=if($RuntimeIdentifier.EndsWith('arm64')){'arm64'}else{'amd64'}
    Assert-AlpineSmoke 'The Podman backend is native Linux for the selected architecture' ($backend.Outcome -eq 'Success' -and ($backend.Stdout -join '').Trim() -ceq "linux $architecture")
    $state.Case='Build the declared image; detailed output is retained in worker.stdout.log and podman.log';Write-WorkspaceJson $status $state
    $receipt=& (Join-Path $WorkspaceRoot 'scripts/New-CiImage.ps1') -RuntimeIdentifier $RuntimeIdentifier -WorkspaceRoot $WorkspaceRoot
    Write-WorkspaceJson (Join-Path $RunDirectory 'image.json') $receipt
    Assert-AlpineSmoke 'The builder returned a local image without publication' ($receipt.Image -cmatch '^(sha256:)?[a-f0-9]{64}$' -and !$receipt.Published)
    $state.Case='Run unchanged-default and explicit-root runtime controls';Write-WorkspaceJson $status $state
    $runtime=& (Join-Path $WorkspaceRoot 'scripts/Invoke-ContainerRuntimeDiagnosis.ps1') -Image $receipt.Image -ExpectedRuntimeIdentifier $RuntimeIdentifier -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $RunDirectory 'runtime') | Select-Object -Last 1
    $report=Get-Content -LiteralPath (Join-Path $runtime.RunDirectory 'summary.json') -Raw -Encoding utf8|ConvertFrom-Json
    $diagnosis=$report.Diagnosis
    $default=@($report.Observations|Where-Object Name -eq Default)
    Assert-AlpineSmoke 'PowerShell starts with the unchanged image defaults' ($default.Count -eq 1 -and $default[0].Outcome -eq 'Success')
    $probe=$default[0].Probe
    $state.Platform=$probe.RuntimeIdentifier
    $locked=Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'build/ci-images.lock.json') -Raw -Encoding utf8|ConvertFrom-Json
    Assert-AlpineSmoke 'The installed PowerShell version matches the locked package' ($probe.PowerShellVersion -ceq ($locked.AlpinePowerShellPackage -replace '-r\d+$',''))
    Assert-AlpineSmoke 'Stable PowerShell uses the locked Microsoft CLR 10' ($probe.FrameworkMajor -eq 10 -and $probe.RuntimeDirectory.StartsWith(('/opt/pwsh-runtime/shared/Microsoft.NETCore.App/'+$locked.AlpineRuntime+'/')))
    Assert-AlpineSmoke 'The actual portable musl RID matches the selected native target' ($probe.RuntimeIdentifier -ceq $RuntimeIdentifier)
    Assert-AlpineSmoke 'The expected musl SQLite asset actually loads' ($probe.Libc -ceq 'Musl' -and $probe.ExpectedNative.Outcome -ceq 'Success' -and $probe.ExpectedNative.HashMatches)
    Assert-AlpineSmoke 'No runtime-root bootstrap correction is needed' (!$diagnosis.BootstrapConfigurationProblem)
    Assert-AlpineSmoke 'Runtime diagnostic container removal was confirmed' ($report.State.Cleanup -ceq 'RemovedOwnedContainer')
    $state.Case='Check the pinned SDK with the same image defaults';$state.ContainerId=$sdkName;Write-WorkspaceJson $status $state
    $sdkAttempted=$true
    $sdk=Invoke-AlpineSmokeNative @('run','--rm','--network=none','--name',$sdkName,'--label',('org.frenchexdev.quietcli2.owner='+$sdkName),'--entrypoint','dotnet',$receipt.Image,'--version')
    $expectedSdk=(Get-Content -LiteralPath (Join-Path $WorkspaceRoot 'global.json') -Raw -Encoding utf8|ConvertFrom-Json).sdk.version
    Assert-AlpineSmoke 'The .NET CLI still starts the pinned SDK under the same defaults' ($sdk.Outcome -eq 'Success' -and ($sdk.Stdout -join '').Trim() -ceq $expectedSdk)
    $state.State='Success'
}catch{$state.State='Failed';$state.Error=$_.ToString();if(!$state.Failed){$state.Failed++}}
finally{
    if($sdkAttempted){
        try{
            $exists=Invoke-AlpineSmokeNative @('container','exists',$sdkName)
            if($exists.ExitCode -eq 0){$null=Invoke-AlpineSmokeNative @('rm','--force',$sdkName);$exists=Invoke-AlpineSmokeNative @('container','exists',$sdkName)}
            $state.Cleanup=if($exists.ExitCode -eq 1){'OwnedProbeAbsent'}else{'Unconfirmed'}
            if($state.Cleanup -eq 'Unconfirmed'){$state.State='Failed';$state.Failed++;$state.Error+='; SDK probe cleanup unconfirmed'}
        }catch{$state.State='Failed';$state.Cleanup='Unconfirmed';$state.Error+='; '+$_.Exception.Message}
    }
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state;Checks=$checks.ToArray();Image=$receipt;Diagnosis=$diagnosis;Sdk=$sdk;Backend=$backend;Qualification='ImageBootstrapSmokeOnly'}
    Write-WorkspaceJson $status $state
}
if($state.State -ne 'Success'){throw "Alpine image smoke failed: $RunDirectory"}
