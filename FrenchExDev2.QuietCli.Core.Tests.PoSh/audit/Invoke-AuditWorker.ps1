# Objectif : Vérifier les corrections de sécurité avec des fixtures synthétiques et des assertions indépendantes.
#requires -Version 7.6
<#
.SYNOPSIS
Runs audit regressions; every applicable check must close its finding for this worker to succeed.
.PARAMETER WorkspaceRoot
QuietCli2 workspace.
.PARAMETER RunDirectory
Dedicated evidence directory; no real secret or user repository is read.
#>
[CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory)
$ErrorActionPreference='Stop';. (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
[void][IO.Directory]::CreateDirectory($RunDirectory)
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh + FrenchExDev2.QuietCli.Git.PoSh';Task='Régressions sécurité et logiciel';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh');Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;ProcessId=$PID;StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');FinishedUtc=$null;State='Running';Passed=0;Failed=0;Case='Starting independent security checks';Error=$null}
$checks=[Collections.Generic.List[object]]::new();Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
$env:PSModulePath=$WorkspaceRoot+[IO.Path]::PathSeparator+$env:PSModulePath
. (Join-Path $WorkspaceRoot 'scripts/TestConfiguration.ps1')
Initialize-QuietTestConfiguration -DatabasePath (Join-Path $RunDirectory 'audit.sqlite')
function Add-AuditEvidence {
    <#
    .SYNOPSIS
    Records an independent expected invariant; failed invariants make the worker fail.
    .PARAMETER Id
    Audit identifier.
    .PARAMETER Resolved
    Whether the required safety invariant holds.
    .PARAMETER Evidence
    Small synthetic facts, never a raw QuietCli result.
    #>
    param([string]$Id,[bool]$Resolved,$Evidence)
    $checks.Add([pscustomobject]@{Id=$Id;Resolved=$Resolved;Evidence=$Evidence})
    if($Resolved){$state.Passed++}else{$state.Failed++}
    $state.Case=$Id;Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
}
$core=$null
try{
    $core=Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1') -PassThru
    $git=Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Git.PoSh/FrenchExDev2.QuietCli.Git.PoSh.psd1') -PassThru
    $dotnet=(Get-Command dotnet -CommandType Application|Select-Object -First 1).Source
    $fixture=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
    $fault=& $core {
        param($dotnet,$fixture)
        $original=Get-Command Send-QuietRequest -CommandType Cmdlet
        $script:AuditOriginalSend=$original;$script:AuditStartCount=0
        Set-Item Function:script:Send-QuietRequest -Value {
            param([hashtable]$Header,[byte[]]$Payload=@())
            $response=& $script:AuditOriginalSend $Header $Payload
            if($Header.Action -eq 'start'){$script:AuditStartCount++;throw [IO.IOException]::new('Synthetic lost start acknowledgement')}
            return $response
        }
        try{
            $r=Invoke-QuietCli -AsObject -Output {param($e,$r)} $dotnet $fixture emit 3
            @{Outcome=$r.Outcome;Complete=$r.Completeness.Source;Effect=$r.Execution.EffectStatus;Starts=$script:AuditStartCount}
        }finally{Remove-Item Function:Send-QuietRequest -Force;Remove-Variable AuditOriginalSend,AuditStartCount -Scope Script}
    } $dotnet $fixture
    Add-AuditEvidence REL-01 ($fault.Outcome -eq 'Failed' -and !$fault.Complete -and $fault.Effect -eq 'Unknown' -and $fault.Starts -eq 1) $fault
    Stop-QuietEngine

    $r=quiet -AsObject -C audit-error -Output {param($e,$r)throw 'AUDIT_SYNTHETIC_SECRET_7f2c'} $dotnet $fixture emit 1
    $leak=& $core {
        $rows=(Send-QuietRequest @{Action='query';From=0L;To=[DateTimeOffset]::UtcNow.AddMinutes(1).ToUnixTimeMilliseconds();Context='audit-error';Generic=$false}).Header.Data.Rows
        @($rows|Where-Object{foreach($error in $_.Error){if($error.PSObject.Properties['Message']){$true}}}).Count
    }
    Add-AuditEvidence SEC-02 ($leak -eq 0 -and $r.Error.Message -eq 'AUDIT_SYNTHETIC_SECRET_7f2c') @{PersistedMessageRows=$leak;LocalDiagnosticPreserved=($r.Error.Message -eq 'AUDIT_SYNTHETIC_SECRET_7f2c')}

    $rejected=& $core {
        try{$null=Send-QuietRequest @{Action='save';Kind='invocation';Metadata=@{InvocationId='nested';Execution=@{Data=@{Synthetic='must-not-be-stored'}}}};$false}
        catch{$_.Exception.Data.Contains('QuietCliRequestRejected')}
    }
    Add-AuditEvidence SEC-03 $rejected @{NestedBusinessShapeRejected=$rejected}

    $pagination=& $core {
        $errors=@(1..128|ForEach-Object{@{Code=('SyntheticDiagnosticIdentifier_'+$_);Phase='Running'}})
        for($index=0;$index -lt 180;$index++){$id='audit-page-'+$index;$null=Send-QuietRequest @{Action='save';Kind='invocation';Metadata=@{InvocationId=$id;RootId=$id;ParentId=$null;SessionId='audit';Context='audit-volume';Role='Infrastructure';Command='synthetic';Outcome='Failed';Sources=@();Error=$errors}}}
        $query=@{Action='query';From=0L;To=[DateTimeOffset]::UtcNow.AddMinutes(1).ToUnixTimeMilliseconds();Context='audit-volume';Generic=$false}
        $ids=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal);$pages=0
        do{$response=(Send-QuietRequest $query).Header.Data;$pages++;foreach($row in $response.Rows){if(!$ids.Add($row.InvocationId)){throw 'DuplicatePageRow'}};if(!$response.Complete){$query.After=$response.After}}while(!$response.Complete)
        @{Rows=$ids.Count;Pages=$pages;Complete=$response.Complete}
    }
    Add-AuditEvidence REL-02 ($pagination.Rows -eq 180 -and $pagination.Pages -gt 1 -and $pagination.Complete) $pagination

    $dotted=& $core {
        param($path)
        [void][IO.File]::WriteAllTextAsync($path,'not executed',[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
        Register-QuietHandler -Id audit-dotted -Definition @{Binary='audit.tool';VersionRange='synthetic';TestVersion={param($v)$true};Probe={param($r)'1.0'};Execute={param($r)'not executed'}}
        try{$runtime=[pscustomobject]@{Request=@{FilePath=$path;Environment=@{}};State=@{}};$null -ne (Resolve-QuietHandler $runtime)}finally{Unregister-QuietHandler -Id audit-dotted}
    } (Join-Path $RunDirectory 'audit.tool')
    Add-AuditEvidence DES-01 $dotted @{DottedBinaryResolved=$dotted;NoBinaryExecuted=$true}

    $package=Join-Path $RunDirectory 'package-probe';[void][IO.Directory]::CreateDirectory($package)
    $zip=[IO.Compression.ZipFile]::Open((Join-Path $package 'Innocent.zip'),[IO.Compression.ZipArchiveMode]::Create)
    $entries=[ordered]@{'Innocent/readme.txt'='synthetic';'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psm1'="[IO.File]::WriteAllText((Join-Path `$PSScriptRoot 'audit-import-marker.txt'),'synthetic')"}
    try{foreach($entry in $entries.GetEnumerator()){$writer=[IO.StreamWriter]::new($zip.CreateEntry($entry.Key).Open(),[Text.UTF8Encoding]::new($false));try{$writer.Write($entry.Value)}finally{$writer.Dispose()}}}finally{$zip.Dispose()}
    $bytes=[Text.Encoding]::UTF8.GetBytes('synthetic')
    Write-WorkspaceJson (Join-Path $package 'Innocent.manifest.json') @{Module='Innocent';Files=@(@{Path='readme.txt';SHA256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes));Bytes=$bytes.Length})}
    $probe=quiet -AsObject -Role Infrastructure -Output {param($e,$r)} pwsh -File (Join-Path $WorkspaceRoot 'scripts/Verify-Distribution.ps1') -PackageDirectory $package -ExtractionDirectory (Join-Path $RunDirectory 'extracted-probe') -TestImport
    $marker=Join-Path $RunDirectory 'extracted-probe/FrenchExDev2.QuietCli.Core.PoSh/audit-import-marker.txt'
    Add-AuditEvidence SEC-01 ($probe.Outcome -ne 'Success' -and !(Test-Path -LiteralPath $marker)) @{Rejected=($probe.Outcome -ne 'Success');UnexpectedCodeExecuted=(Test-Path -LiteralPath $marker)}
    . (Join-Path $PSScriptRoot 'Package.Tests.ps1')
    foreach($check in Invoke-AuditPackageChecks $WorkspaceRoot $RunDirectory){Add-AuditEvidence $check.Id $check.Resolved $check.Evidence}

    $changes=& $git {$before=@(@{Name='refs/heads/Feature';ObjectId=('1'*40)},@{Name='refs/heads/feature';ObjectId=('2'*40)});$after=@(@{Name='refs/heads/Feature';ObjectId=('3'*40)},@{Name='refs/heads/feature';ObjectId=('2'*40)});@(Get-QuietGitRefChanges $before $after).Count}
    Add-AuditEvidence REL-03 ($changes -eq 1) @{ExpectedChanges=1;ObservedChanges=$changes}

    $temporary=Join-Path $RunDirectory 'owned-temp';[void][IO.Directory]::CreateDirectory($temporary)
    $saved=@{TEMP=$env:TEMP;TMP=$env:TMP;TMPDIR=$env:TMPDIR};$env:TEMP=$temporary;$env:TMP=$temporary;$env:TMPDIR=$temporary
    try{
        $gitPath=(Get-Command git -CommandType Application|Select-Object -First 1).Source
        $failed=& $git {param($file,$directory)$runtime=[pscustomobject]@{Request=@{WorkingDirectory=$directory;Environment=@{};FilePath=$file;TimeoutSeconds=1;Transport='Pipe'}};Invoke-QuietGitBlobOutput $runtime @('--version') 'synthetic'} $gitPath (Join-Path $RunDirectory 'nonexistent-directory')
        $left=@(Get-ChildItem -LiteralPath $temporary -Recurse -File).Count
        Add-AuditEvidence REL-04 (!$failed.ContainsKey('File') -and $null -eq $failed.Artifact -and $left -eq 0) @{InternalStreamReturned=$failed.ContainsKey('File');RemainingFiles=$left}
        if(!$IsWindows){
            $successful=& $git {param($file,$directory)$runtime=[pscustomobject]@{Request=@{WorkingDirectory=$directory;Environment=@{};FilePath=$file;TimeoutSeconds=5;Transport='Pipe'}};Invoke-QuietGitBlobOutput $runtime @('--version') 'synthetic'} $gitPath $RunDirectory
            try{
                $fileMode=[IO.File]::GetUnixFileMode($successful.Artifact.Path)
                $directoryMode=[IO.File]::GetUnixFileMode([IO.Path]::GetDirectoryName($successful.Artifact.Path))
                Add-AuditEvidence SEC-04 ([int]$fileMode -eq 384 -and [int]$directoryMode -eq 448) @{FileMode=[int]$fileMode;DirectoryMode=[int]$directoryMode}
            }finally{Remove-QuietGitArtifact $successful.Artifact}
        }
    }finally{foreach($name in $saved.Keys){[Environment]::SetEnvironmentVariable($name,$saved[$name])}}

    $held=@{}
    $r=quiet -AsObject -State $held -Output {param($e,$r)$r.State.Runtime=$r} $dotnet $fixture emit 1
    $held.Runtime.Execution.Outcome='SyntheticTampering'
    $immutable=$false;try{$r.Execution.State='Running'}catch{$immutable=$true}
    $replaceBlocked=$false;try{$r.Execution=@{State='Running'}}catch{$replaceBlocked=$true}
    Add-AuditEvidence DES-02 ($immutable -and $replaceBlocked -and $r.Execution.Native.Outcome -eq 'Success') @{ImmutableSnapshot=$immutable;ReplacementBlocked=$replaceBlocked;DetachedFromRuntime=($r.Execution.Native.Outcome -eq 'Success')}

    # Independent C# stream fixture cancels a source that never returns EOF; no timing-sensitive child process is needed.
    $assembly=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/engine-tests/QuietCli.Engine.Tests.dll'
    $native=Join-Path $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/resources/runtime/runtimes/'+[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier+'/native')
    $checksResult=quiet -AsObject -Role Infrastructure -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} $dotnet $assembly $native
    $drain=@($checksResult.Data.Cases|Where-Object Name -EQ 'drain cancellation cannot claim EOF')
    Add-AuditEvidence REL-05 ($checksResult.Outcome -eq 'Success' -and $drain.Count -eq 1 -and $drain[0].State -eq 'Passed') @{IndependentDrainCase=($drain.Count -eq 1);CSharpPassed=$checksResult.Data.Passed;CSharpFailed=$checksResult.Data.Failed}

    Stop-QuietEngine
    $ipc=& $core {
        $name='quietcli2-ipc-audit-'+[guid]::NewGuid().ToString('N')
        $server=[IO.Pipes.NamedPipeServerStream]::new($name,[IO.Pipes.PipeDirection]::In,1,[IO.Pipes.PipeTransmissionMode]::Byte,([IO.Pipes.PipeOptions]::Asynchronous -bor [IO.Pipes.PipeOptions]::CurrentUserOnly))
        $client=[IO.Pipes.NamedPipeClientStream]::new('.',$name,[IO.Pipes.PipeDirection]::Out,[IO.Pipes.PipeOptions]::Asynchronous)
        $accept=$server.WaitForConnectionAsync()
        [void]$client.ConnectAsync().GetAwaiter().GetResult();[void]$accept.GetAwaiter().GetResult()
        $engine=[FrenchExDev2.QuietCli.EngineConnection]::new();$engine.Mode='Process';$engine.Input=[IO.MemoryStream]::new();$engine.Output=$server;[FrenchExDev2.QuietCli.QuietSession]::Engine=$engine
        $old=(Get-QuietTestConfiguration).Values['engine.ipcTimeoutSeconds'];(Get-QuietTestConfiguration).Values['engine.ipcTimeoutSeconds']='0.1'
        $watch=[Diagnostics.Stopwatch]::StartNew();$cancelled=$false
        try{$null=Send-QuietRequest @{Action='hello'}}catch{$cancelled=$engine.Broken}
        finally{$engine.Input.Dispose();$server.Dispose();$client.Dispose();[FrenchExDev2.QuietCli.QuietSession]::Engine=$null;(Get-QuietTestConfiguration).Values['engine.ipcTimeoutSeconds']=$old}
        @{Disconnected=$cancelled;Milliseconds=$watch.Elapsed.TotalMilliseconds}
    }
    Add-AuditEvidence REL-06 ($ipc.Disconnected -and $ipc.Milliseconds -lt 2000) $ipc

    $bootstrap=quiet -AsObject -Role Infrastructure -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Probe-Bootstrap.ps1') -WorkspaceRoot $WorkspaceRoot
    Add-AuditEvidence SEC-05 ($bootstrap.Outcome -eq 'Success' -and $bootstrap.Data.Rejected -and $bootstrap.Data.ManagedDeltaBytes -lt 8388608) $bootstrap.Data
    $state.State=if($state.Failed){'Failed'}else{'Success'}
}catch{$state.State='Crash';$state.Failed++;$state.Error=$_.ToString();$state.Case='Regression harness error'}
finally{
    if($core){try{Stop-QuietEngine}catch{}}
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state;Checks=$checks.ToArray();Resolved=@($checks|Where-Object Resolved).Count;Unresolved=@($checks|Where-Object{!$_.Resolved}).Count}
    Write-WorkspaceJson (Join-Path $RunDirectory 'status.json') $state
}
[pscustomobject]@{State=$state.State;Checks=$checks.Count;Failed=$state.Failed}|ConvertTo-Json -Compress
if($state.State -ne 'Success'){exit 1}
