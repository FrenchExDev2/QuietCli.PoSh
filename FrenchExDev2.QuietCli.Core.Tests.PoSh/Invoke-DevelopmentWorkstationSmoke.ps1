#requires -Version 7.6
<#
.SYNOPSIS
Runs read-only Windows checks and disposable Linux workstation installations with a visible monitor.
.PARAMETER WorkspaceRoot
Checkout mounted read-only in disposable containers.
.PARAMETER RunDirectory
New external report directory, defaulting to the shared temporary report root.
.PARAMETER Targets
Host checks to execute. Native ARM64 is covered separately by policy fixtures.
.PARAMETER Worker
Internal background worker; use the ordinary entry point to retain the visible monitor.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$RunDirectory,[ValidateSet('Windows','Debian','Ubuntu','Alpine','Fedora')][string[]]$Targets=@('Windows','Debian','Ubuntu','Alpine','Fedora'),[switch]$Worker)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
if(!$Worker){
    if(!$IsWindows){throw 'Launch the visible smoke monitor from Windows.'}
    if(!$RunDirectory){$RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'workstation') ([guid]::NewGuid().ToString('N'))}
    if(Test-Path -LiteralPath $RunDirectory){throw 'WorkstationSmokeRunExists'}
    [void][IO.Directory]::CreateDirectory($RunDirectory)
    $snapshot=Join-Path $RunDirectory 'source'
    [void][IO.Directory]::CreateDirectory($snapshot)
    foreach($directory in @('scripts','build')){Copy-Item -LiteralPath (Join-Path $WorkspaceRoot $directory) -Destination $snapshot -Recurse}
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'global.json') -Destination $snapshot
    $gitLocks=Join-Path $snapshot 'FrenchExDev2.QuietCli.Git.PoSh/metadata'
    [void][IO.Directory]::CreateDirectory($gitLocks)
    Copy-Item -LiteralPath (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/metadata/locks') -Destination $gitLocks -Recurse
    Write-WorkspaceJson (Join-Path $RunDirectory 'source-inputs.json') @(Get-ChildItem -LiteralPath $snapshot -File -Recurse|ForEach-Object {@{Path=[IO.Path]::GetRelativePath($snapshot,$_.FullName).Replace('\','/');SHA256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
    Write-WorkspaceJson (Join-Path $RunDirectory 'targets.json') @($Targets)
    $runner=Join-Path $PSHOME 'pwsh.exe'
    $process=Start-Process $runner -WindowStyle Hidden -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $PSCommandPath),'-WorkspaceRoot',(ConvertTo-CiArgument $WorkspaceRoot),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory),'-Worker') -RedirectStandardOutput (Join-Path $RunDirectory 'worker.stdout.log') -RedirectStandardError (Join-Path $RunDirectory 'worker.stderr.log')
    $monitorPath=Join-Path $WorkspaceRoot 'scripts/Watch-Tests.ps1'
    $monitor=Start-Process $runner -WindowStyle Normal -PassThru -ArgumentList @('-File',(ConvertTo-CiArgument $monitorPath),'-RunDirectory',(ConvertTo-CiArgument $RunDirectory)) -RedirectStandardError (Join-Path $RunDirectory 'monitor.stderr.log')
    'Monitor: pwsh -File '+(ConvertTo-CiArgument $monitorPath)+' -RunDirectory '+(ConvertTo-CiArgument $RunDirectory)
    $summary=Wait-WorkspaceWorker -Worker $process -Monitor $monitor -Runner $runner -RunDirectory $RunDirectory -WorkspaceRoot $WorkspaceRoot -TimeoutSeconds 7200
    [pscustomobject]@{State=$summary.State.State;RunDirectory=$RunDirectory;Runs=$summary.State.Runs}
    if($summary.State.State -ne 'Success'){throw "Workstation smoke failed: $RunDirectory"};return
}
$Targets=@(Get-Content -LiteralPath (Join-Path $RunDirectory 'targets.json') -Raw -Encoding utf8|ConvertFrom-Json)
Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/WorkstationResources.psm1')
$ownership=Register-WorkstationRun $RunDirectory $WorkspaceRoot
$runLease=[IO.FileStream]::new((Join-Path $RunDirectory 'run.lease'),[IO.FileMode]::CreateNew,[IO.FileAccess]::ReadWrite,[IO.FileShare]::Read)
$runLease.Lock(0,1)
$smokeState=@{Project='FrenchExDev2.QuietCli.Core.Tests.PoSh';Task='Development workstation installation smoke';Workspace=$WorkspaceRoot;ProjectDirectory=$PSScriptRoot;Platform='Windows + Linux x64';State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');ProcessId=$PID;Passed=0;Failed=0;Case='Starting';Error=$null;Runs=@()}
$receipts=[Collections.Generic.List[object]]::new();$statusPath=Join-Path $RunDirectory 'status.json'
Write-WorkspaceJson $statusPath $smokeState
function Invoke-SmokeProcess {
    <#
    .SYNOPSIS
    Streams one owned process and saves output-line heartbeats for the monitor.
    .PARAMETER FilePath
    Explicit tool.
    .PARAMETER Arguments
    Exact argument vector.
    #>
    param([string]$FilePath,[string[]]$Arguments)
    $progress=@{Lines=0;Last=[DateTimeOffset]::UtcNow}
    $result=Invoke-CiProcess $FilePath $Arguments -WorkingDirectory $WorkspaceRoot -TimeoutSeconds 3600 -State $progress -OnOutput {
        param($e,$p)
        $p.Lines++;[void][Console]::Out.WriteLineAsync($e.Text).GetAwaiter().GetResult()
        if(([DateTimeOffset]::UtcNow-$p.Last).TotalSeconds -ge 3){$smokeState.Case="Output lines: $($p.Lines) | $FilePath";Write-WorkspaceJson $statusPath $smokeState;$p.Last=[DateTimeOffset]::UtcNow}
    }
    if($result.Outcome -ne 'Success'){throw "SmokeProcessFailed: $FilePath exit $($result.ExitCode) $($result.Outcome)"}
}
try{
    if(@($Targets|Where-Object {$_ -cne 'Windows'}).Count){$ownership=Register-WorkstationRun $RunDirectory $WorkspaceRoot -PodmanIdentity (Get-WorkstationPodmanIdentity)}
    if('Windows' -in $Targets){
        $row=@{Platform='Windows x64';State='Running';Identity="PID $PID";StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null};$smokeState.Runs+=,$row;Write-WorkspaceJson $statusPath $smokeState
        $missing=Join-Path $RunDirectory 'windows-control-must-not-exist'
        $installer=Join-Path $WorkspaceRoot 'scripts/Install-DevelopmentWorkstation.ps1'
        $before=$env:PATH;$environmentRoot=$env:DOTNET_ROOT
        foreach($options in @(@{CheckOnly=$true},@{WhatIf=$true;Insiders=$true})){
            $report=& $installer -InstallRoot $missing -SkipEditor -SkipContainers -SkipNativeTools -SkipProfilers @options
            if(Test-Path -LiteralPath $missing){throw 'ControlModeWroteInstallRoot'}
            if($env:PATH -cne $before -or $env:DOTNET_ROOT -cne $environmentRoot){throw 'ControlModeChangedEnvironment'}
            if($report.State -notin @('Ready','NeedsInstallation')){throw 'ControlModeInvalidReport'}
            [void]$receipts.Add(@{Platform='Windows';Mode=$options.Keys -join ',';State=$report.State;Components=$report.Components})
        }
        $smokeState.Case='Verified wrkflw archive, local listing and valid/invalid workflow definitions';Write-WorkspaceJson $statusPath $smokeState
        $toolRoot=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'toolchains') 'wrkflw-0.8.0'
        $target=Get-DevelopmentHost
        $spec=Get-DevelopmentSpecification $WorkspaceRoot $target
        $workflowPlan=New-DevelopmentPlan $target $WorkspaceRoot $toolRoot $spec -Skipped @('Editor','Containers','Native','Profilers')
        # Only this isolated user tool is installed; other workstation components remain untouched.
        & (Get-Module DevelopmentWorkstation) {param($plan) Install-DevelopmentWrkflw $plan} $workflowPlan
        $workflowInventory=Get-DevelopmentInventory $workflowPlan
        if($workflowInventory.Workflows.State -cne 'Ready'){throw 'WrkflwInstalledVersionNotVerified'}
        $fixtureRoot=Join-Path $RunDirectory 'wrkflw-fixture'
        $workflowDirectory=Join-Path $fixtureRoot '.github/workflows'
        [void][IO.Directory]::CreateDirectory($workflowDirectory)
        $validPath=Join-Path $workflowDirectory 'ci.yml'
        $invalidPath=Join-Path $fixtureRoot 'invalid.yml'
        $valid="name: Local Unicode-é fixture`non: push`njobs:`n  check:`n    runs-on: ubuntu-latest`n    steps:`n      - run: echo fixture`n"
        [void][IO.File]::WriteAllTextAsync($validPath,$valid,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        [void][IO.File]::WriteAllTextAsync($invalidPath,"jobs: [`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        $tool=$workflowInventory.Workflows.Path
        $listing=Invoke-DevelopmentCommand $tool @('list','--jobs') $fixtureRoot -Capture -AllowFailure -TimeoutSeconds 30
        $validResult=Invoke-DevelopmentCommand $tool @('validate',$validPath) $fixtureRoot -Capture -AllowFailure -TimeoutSeconds 30
        $invalidResult=Invoke-DevelopmentCommand $tool @('validate',$invalidPath) $fixtureRoot -Capture -AllowFailure -TimeoutSeconds 30
        if($listing.Outcome -cne 'Success' -or !@($listing.Lines|Where-Object {$_ -match 'check'}).Count){throw 'WrkflwLocalJobListingFailed'}
        if($validResult.Outcome -cne 'Success' -or $validResult.ExitCode -ne 0){throw 'WrkflwValidDefinitionRejected'}
        if($invalidResult.Outcome -ceq 'Success' -or $invalidResult.ExitCode -ne 1){throw 'WrkflwMalformedDefinitionAccepted'}
        [void]$receipts.Add(@{Platform='Windows';Mode='WrkflwArchiveAndDefinitions';Version=$workflowInventory.Workflows.Version;ArtifactSHA256=$spec.Wrkflw.Artifact.SHA256;ToolPath=$tool;ListingExitCode=$listing.ExitCode;ValidDefinitionExitCode=$validResult.ExitCode;InvalidDefinitionExitCode=$invalidResult.ExitCode;Scope='Real native archive/version/list/validate only; no workflow steps, containers or remote execution'})
        $row.State='Success';$row.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');$smokeState.Passed++;Write-WorkspaceJson $statusPath $smokeState
    }
    $guest=@'
$ErrorActionPreference='Stop'
Set-Location /workspace
$name=$env:WORKSTATION_TARGET
$root='/evidence/install-'+$name
$options=@{InstallRoot=$root;SkipEditor=$true;SkipContainers=$true}
$first=./scripts/Install-DevelopmentWorkstation.ps1 @options
if($first.State -ne 'Ready'){throw 'GuestFirstInstallationIncomplete'}
. $first.ActivationScript
# Activation must also preserve a framework-dependent PowerShell host on Alpine.
. ./scripts/lib/Ci.Process.psm1
if((Invoke-CiProcess (Join-Path $PSHOME 'pwsh') @('-Command','[Environment]::Version.ToString()')).Outcome -ne 'Success'){throw 'GuestActivatedPowerShellFailed'}
$check=./scripts/Install-DevelopmentWorkstation.ps1 @options -CheckOnly
if($check.State -ne 'Ready' -or $check.Actions.Count){throw 'GuestInstalledInventoryIncomplete'}
$second=./scripts/Install-DevelopmentWorkstation.ps1 @options
if($second.State -ne 'Ready' -or $second.Actions.Count){throw 'GuestIdempotenceFailed'}
. ./scripts/lib/Ci.Process.psm1
if((Invoke-CiProcess dotnet @('--version') -WorkingDirectory /workspace).Outcome -ne 'Success'){throw 'GuestActivatedSdkFailed'}
$source='/evidence/fuzz-smoke-'+$name+'.c'
$binary='/evidence/fuzz-smoke-'+$name
$c='#include <stddef.h>'+[char]10+'int LLVMFuzzerTestOneInput(const unsigned char *data, size_t size) { (void)data; (void)size; return 0; }'+[char]10
[IO.File]::WriteAllTextAsync($source,$c,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
if((Invoke-CiProcess clang @('-fsanitize=fuzzer,address,undefined',$source,'-o',$binary)).Outcome -ne 'Success'){throw 'GuestSanitizerLinkFailed'}
if((Invoke-CiProcess $binary @('-runs=32','-rss_limit_mb=0')).Outcome -ne 'Success'){throw 'GuestSanitizerRuntimeFailed'}
$result=@{Platform=$name;RuntimeIdentifier=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;Architecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString().ToLowerInvariant();PowerShell=$PSVersionTable.PSVersion.ToString();First=$first;Check=$check;Second=$second;SanitizerSmokeRuns=32;Scope='Real system packages, SDK archive, Zig, profiling cache, Git fallback when necessary; editor/Podman excluded inside disposable guest'}
[IO.File]::WriteAllTextAsync(('/evidence/'+$name+'.json'),($result|ConvertTo-Json -Depth 15)+[char]10,[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
'@
    [void][IO.File]::WriteAllTextAsync((Join-Path $RunDirectory 'guest.ps1'),$guest.Replace("`r`n","`n")+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
    # Repository CI images supply the matching PowerShell binaries, not workstation source files.
    $glibc='ghcr.io/frenchexdev2/quietcli2-ci-debian-x64:125b77f979a16f61399cbf12c7fee43c66f5ebc034e690ffc602c37d199771b4'
    $musl='ghcr.io/frenchexdev2/quietcli2-ci-alpine-x64:589f46af81426b1c91b57ac2e833fdfe417599cf3ab704bbc02e39a2ca151636'
    $bases=@{Debian='docker.io/library/debian:12-slim';Ubuntu='docker.io/library/ubuntu:24.04';Fedora='registry.fedoraproject.org/fedora:43'}
    foreach($target in $Targets|Where-Object {$_ -cne 'Windows'}){
        $name='quietcli-workstation-'+$target.ToLowerInvariant()+'-'+[guid]::NewGuid().ToString('N').Substring(0,8)
        $row=@{Platform="$target x64";State='Running';Identity=$name;StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null};$smokeState.Runs+=,$row;$smokeState.Case="Prepare $target";Write-WorkspaceJson $statusPath $smokeState
        try{
            $image=$musl
            Add-WorkstationResource $RunDirectory Container $name
            if($target -cne 'Alpine'){
                $install=if($target -ceq 'Fedora'){'dnf install -y ca-certificates libicu openssl-libs krb5-libs libgcc libstdc++ zlib-ng-compat tar gzip'}else{'apt-get update && apt-get install -y ca-certificates libicu'+$(if($target -ceq 'Debian'){'72 libssl3'}else{'74 libssl3t64'})+' libgssapi-krb5-2 libstdc++6 zlib1g tar gzip'}
                $containerfile=@("FROM $glibc AS host","FROM $($bases[$target])","RUN $install",'COPY --from=host /opt/powershell /opt/powershell','ENV PATH=/opt/powershell:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin','ENTRYPOINT ["pwsh"]') -join "`n"
                $recipe=Join-Path $RunDirectory ($target+'.Containerfile');[void][IO.File]::WriteAllTextAsync($recipe,$containerfile+"`n",[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
                $image='localhost/'+$name
                Add-WorkstationResource $RunDirectory Image $image
                Invoke-SmokeProcess podman @('build','--pull=missing','--label',('io.frenchexdev.quietcli.workstation.run='+$ownership.RunId),'--tag',$image,'--file',$recipe,$RunDirectory)
            }
            $smokeState.Case="Install and check $target";Write-WorkspaceJson $statusPath $smokeState
            $bootstrapRuntime=if($target -ceq 'Alpine'){@('--env','DOTNET_ROOT=/usr/lib/dotnet')}else{@()}
            Invoke-SmokeProcess podman (@('run','--name',$name,'--rm','--label',('io.frenchexdev.quietcli.workstation.run='+$ownership.RunId),'--env',"WORKSTATION_TARGET=$target",'--env','PATH=/opt/powershell:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin')+$bootstrapRuntime+@('--volume',((Join-Path $RunDirectory 'source')+':/workspace:ro'),'--volume',($RunDirectory+':/evidence:rw'),$image,'-File','/evidence/guest.ps1'))
            $receipt=Get-Content -LiteralPath (Join-Path $RunDirectory ($target+'.json')) -Raw -Encoding utf8|ConvertFrom-Json
            $expectedRid=if($target -ceq 'Alpine'){'linux-musl-x64'}else{'linux-x64'}
            if($receipt.Architecture -cne 'x64' -or $receipt.First.Target.Rid -cne $expectedRid){throw 'GuestArchitectureMismatch'}
            [void]$receipts.Add($receipt);$row.State='Success';$smokeState.Passed++
        }catch{$row.State='Failed';$row.Error=$_.Exception.Message;$smokeState.Failed++;[Console]::Error.WriteLine($_.Exception.Message)}
        $row.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o');Write-WorkspaceJson $statusPath $smokeState
    }
    $smokeState.State=if($smokeState.Failed){'Failed'}else{'Success'}
}catch{$smokeState.State='Crash';$smokeState.Error=$_.Exception.Message;$smokeState.Failed++}
finally{
    foreach($run in $smokeState.Runs){if($run.State -eq 'Running'){$run.State=$smokeState.State;$run.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')}}
    $smokeState.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    try{$ownership=Complete-WorkstationRun $RunDirectory $smokeState.State}catch{$smokeState.Error='Resource receipt failure: '+$_.Exception.Message;$smokeState.State='Failed'}
    if(@($ownership.Resources|Where-Object State -NotIn @('Removed','Absent')).Count){$smokeState.State='Failed';$smokeState.Error='Owned resources remain protected; see ownership.json';$smokeState.Failed++}
    $runLease.Dispose()
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$smokeState;Receipts=@($receipts);Ownership=$ownership}
    Write-WorkspaceJson $statusPath $smokeState
}
if($smokeState.State -ne 'Success'){throw "Workstation smoke failed: $RunDirectory"}
