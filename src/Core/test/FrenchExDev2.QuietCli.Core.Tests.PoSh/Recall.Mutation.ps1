function Invoke-QuietRecallMutation {
    <#
    .SYNOPSIS
    Builds source-checked targeted Recall mutants in owned external directories.
    .PARAMETER WorkspaceRoot
    Original source root, never mutated by this campaign.
    .PARAMETER RunDirectory
    Shared monitored report directory retaining source, logs and outcomes.
    .PARAMETER OnProgress
    Existing visible monitor callback.
    .PARAMETER MutationName
    Optional exact mutation names for a focused run.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[scriptblock]$OnProgress,[string[]]$MutationName=@())
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
    $mutants=@(
        @{Name='iec-factor';File='RecallOptions.cs';From='"KIB" => 1024L';To='"KIB" => 1000L'},
        @{Name='head-byte-loss';File='RecallCapture.cs';From='options.MaximumBytes ?? long.MaxValue';To='(options.MaximumBytes ?? long.MaxValue) - 1'},
        @{Name='tail-byte-duplication';File='RecallCapture.cs';From='first.Slice(remove, first.ByteCount - remove)';To='first.Slice(0, first.ByteCount - remove)'},
        @{Name='mutable-buffer';File='RecallCapture.cs';From='public byte[] Bytes => (byte[])bytes.Clone();';To='public byte[] Bytes => bytes;'},
        @{Name='false-completeness';File='RecallCapture.cs';From='public bool CaptureComplete => OmittedBytes == 0;';To='public bool CaptureComplete => true;'},
        @{Name='wrong-evidence-offset';File='RecallReader.cs';From='return new(capture.CaptureId, stream, offset, length);';To='return new(capture.CaptureId, stream, offset + 1, length);'},
        @{Name='ignore-content-integrity';File='RecallJournalReader.cs';From='!CryptographicOperations.FixedTimeEquals(checksum.GetHashAndReset(), hash)';To='false'},
        @{Name='omit-byte-count';File='RecallCapture.cs';From='public long OmittedBytes => ReceivedBytes - RetainedBytes;';To='public long OmittedBytes => 0;'}
        @{Name='event-order';File='RecallCapture.cs';From='head.Concat(tail), received';To='head.Concat(tail).Reverse(), received'}
        @{Name='drop-journal-bytes';File='RecallJournalWriter.cs';From='item.Content.Span.Slice(at, count).CopyTo(frame.AsSpan(RecallJournalReader.HeaderLength));';To='frame.AsSpan(RecallJournalReader.HeaderLength, count).Clear();'}
        @{Name='wrong-journal-stream';File='RecallJournalReader.cs';From='1 => "stdout"';To='1 => "stderr"'}
        @{Name='lose-durable-argv';File='RecallStore.cs';From='name ?? capture.RecallName, capture.Settings, capture.ArgvString';To='name ?? capture.RecallName, capture.Settings'}
        @{Name='durability-counter';File='RecallJournalWriter.cs';From='DurableBytes = metadata.StoredBytes';To='DurableBytes = 0'}
        @{Name='ignore-compression-level';File='RecallZipWriter.cs';From='CompressionLevel = compression';To='CompressionLevel = 0'}
        @{Name='lose-uncheckpointed-records';File='RecallStore.cs';From='active ? metadata.JournalLength : length';To='metadata.JournalLength'}
        @{Name='hide-interrupted-source';File='RecallStore.cs';From='State = active ? "Recording" : metadata.State == "Failed" ? "Failed" : "Interrupted", SourceComplete = false';To='State = active ? "Recording" : metadata.State == "Failed" ? "Failed" : "Interrupted", SourceComplete = true'}
        @{Name='wrong-catalog-identity';File='RecallStore.cs';From='if (capture.RecallId != expected)';To='if (false)'}
        @{Name='tail-ignores-checkpoint';File='RecallJournalReader.cs';From='when (recoverTail && start >= durableLength)';To='when (recoverTail)'}
        @{Name='tail-accepts-garbage';File='RecallJournalReader.cs';From='if (zero) return true;';To='return true;'}
        @{Name='input-guard-in-recall';File='Cmdlets/RuntimeCommands.cs';From='if (IsRecall) throw new InvalidOperationException("ProcessInputUnavailableDuringRecall");';To='if (false) throw new InvalidOperationException("ProcessInputUnavailableDuringRecall");'}
        @{Name='native-guard-in-recall';File='Cmdlets/InvocationCommands.cs';From='if (QuietCallState.RecallDepth > 0) throw new InvalidOperationException("NativeExecutionUnavailableDuringRecall");';To='if (false) throw new InvalidOperationException("NativeExecutionUnavailableDuringRecall");'}
        @{Name='compression-upper-bound';File='Cmdlets/ArgumentCommands.cs';From='level >= 0 && level <= 9';To='level >= 0'}
        @{Name='tail-accepts-inner-torn-record';File='RecallJournalReader.cs';From='return start + HeaderLength + count + HashLength == limit;';To='return true;'}
    )
    if($MutationName.Count){
        foreach($name in $MutationName){if($name -cnotin $mutants.Name){throw ('UnknownRecallMutant: '+$name)}}
        $mutants=@($mutants|Where-Object Name -CIn $MutationName)
    }
    $results=[Collections.Generic.List[object]]::new();$passed=0;$failed=0
    foreach($mutation in @(@{Name='baseline'})+$mutants){
        $destination=Join-Path $RunDirectory ('mutation/'+$mutation.Name)
        [void][IO.Directory]::CreateDirectory($destination)
        foreach($relative in @('src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine','src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests','src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/recall-tools')){
            $target=Join-Path $destination $relative;[void][IO.Directory]::CreateDirectory($target)
            foreach($file in Get-QuietSourceFiles (Join-Path $WorkspaceRoot $relative)){if($file.Path -notmatch '\.(cs|csproj)$'){continue};$to=Join-Path $target $file.Path;[void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($to));Copy-Item -LiteralPath (Join-Path (Join-Path $WorkspaceRoot $relative) $file.Path) -Destination $to}
        }
        foreach($relative in @('global.json','Directory.Build.props','Directory.Packages.props','src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/protocol.json')){
            [IO.File]::Copy([IO.Path]::Combine($WorkspaceRoot,$relative),[IO.Path]::Combine($destination,$relative))
        }
        $outcome='InfrastructureFailed';$detail=$null
        try{
            if($mutation.Name -ne 'baseline'){
                $path=Join-Path $destination ('src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/engine/'+$mutation.File)
                $text=[IO.File]::ReadAllText($path)
                if(($text.Split([string[]]@($mutation.From),[StringSplitOptions]::None).Count-1) -ne 1){throw 'MutationSourceMismatch'}
                [void][IO.File]::WriteAllTextAsync($path,$text.Replace($mutation.From,$mutation.To),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            }
            $output=Join-Path $destination 'output'
            $log=@{Text=[Text.StringBuilder]::new()}
            $artifacts=[IO.Path]::Combine($destination,'artifacts')
            $project='src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests/QuietCli.Engine.Tests.csproj'
            $buildProperties=@('-p:TargetFrameworks=net11.0','-p:UseAppHost=false','--artifacts-path',$artifacts)
            # The workspace build has already populated the package cache for this framework.
            $offlineFeed=[IO.Path]::Combine($destination,'offline-feed')
            [void][IO.Directory]::CreateDirectory($offlineFeed)
            $restoreArguments=@('restore',$project,'-p:NuGetAudit=false','--source',$offlineFeed,'--nologo')+$buildProperties
            $restore=Invoke-CiProcess -FilePath dotnet -ArgumentList $restoreArguments -WorkingDirectory $destination -TimeoutSeconds 90 -State $log -OnOutput {param($e,$s)[void]$s.Text.AppendLine($e.Text)}
            [IO.File]::WriteAllText([IO.Path]::Combine($destination,'restore.log'),$log.Text.ToString().Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false))
            if($restore.Outcome -ne 'Success'){
                if($restore.Outcome -eq 'Timeout'){$outcome='Timeout'}
                throw 'MutantRestoreFailed'
            }
            $log.Text.Clear()|Out-Null
            $buildArguments=@('build',$project,'--no-restore','-f','net11.0','-c','Release','-o',$output,'--nologo')+$buildProperties
            $build=Invoke-CiProcess -FilePath dotnet -ArgumentList $buildArguments -WorkingDirectory $destination -TimeoutSeconds 90 -State $log -OnOutput {param($e,$s)[void]$s.Text.AppendLine($e.Text)}
            [void][IO.File]::WriteAllTextAsync((Join-Path $destination 'build.log'),$log.Text.ToString().Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            if($build.Outcome -ne 'Success'){$outcome=if($build.Outcome -eq 'Timeout'){'Timeout'}else{'Invalid'};throw 'MutantBuildFailed'}
            $log.Text.Clear()|Out-Null
            $test=Invoke-CiProcess -FilePath dotnet -ArgumentList @((Join-Path $output 'QuietCli.Engine.Tests.dll'),'--recall-only') -WorkingDirectory $destination -TimeoutSeconds 45 -State $log -OnOutput {param($e,$s)[void]$s.Text.AppendLine($e.Text)}
            [void][IO.File]::WriteAllTextAsync((Join-Path $destination 'test.log'),$log.Text.ToString().Replace("`r`n","`n"),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            if($test.Outcome -eq 'Timeout'){$outcome='Timeout'}else{
                $report=$log.Text.ToString()|ConvertFrom-Json
                if($mutation.Name -eq 'baseline'){$outcome=if($test.Outcome -eq 'Success' -and $report.Failed -eq 0){'Passed'}else{'BaselineFailed'}}
                else{$outcome=if($report.Failed -gt 0){'Killed'}elseif($test.Outcome -eq 'Success'){'Survived'}else{'Crash'}}
            }
        }catch{$detail=$_.ToString()}
        if($outcome -in @('Passed','Killed')){$passed++}else{$failed++}
        $results.Add(@{Name=$mutation.Name;Outcome=$outcome;Error=$detail})
        Write-WorkspaceJson (Join-Path $RunDirectory 'recall-mutation.json') $results.ToArray()
        if($OnProgress){& $OnProgress ($mutation.Name+': '+$outcome) $outcome $passed $failed}
        if($mutation.Name -eq 'baseline' -and $outcome -ne 'Passed'){break}
    }
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=$passed;Failed=$failed;Cases=$results.ToArray();Scope='Twenty-two C# source-checked targeted mutants; replay mutants live in the configuration/delivery catalogue. Not exhaustive mutation coverage.'}
}
