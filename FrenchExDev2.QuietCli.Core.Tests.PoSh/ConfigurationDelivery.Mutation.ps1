function Invoke-QuietConfigurationDeliveryEngine {
    <#
    .SYNOPSIS
    Executes the compiled baseline and bounded source mutants using owned source copies.
    .PARAMETER WorkspaceRoot
    Built monorepo.
    .PARAMETER RunDirectory
    Owned output directory.
    .PARAMETER Mutation
    Enables the targeted source catalogue.
    .PARAMETER OnProgress
    Shared visible-monitor callback.
    .PARAMETER MutationName
    Optional exact mutant names for a targeted development campaign; the report records partial catalogue coverage.
    #>
    param([string]$WorkspaceRoot,[string]$RunDirectory,[switch]$Mutation,[scriptblock]$OnProgress,[string[]]$MutationName=@())
    $native=Join-Path $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/resources/runtime/runtimes/'+[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier+'/native')
    $yaml=Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/resources/yaml/YamlDotNet.dll'
    $runCases={
        param($assembly)
        $capture=@{Report=$null}
        $execution=Invoke-CiProcess -FilePath dotnet -ArgumentList @($assembly,$native,'--configuration-delivery-only',$yaml) -TimeoutSeconds 60 -State $capture -OnOutput {
            param($line,$state)
            if($line.Stream -eq 'stdout' -and $line.Text.StartsWith('{"Passed":')){$state.Report=$line.Text|ConvertFrom-Json}
        }
        if(!$capture.Report -or $execution.Outcome -eq 'Timeout'){throw 'ConfigurationDeliveryEngineCrashedOrTimedOut'}
        return [pscustomobject]@{Execution=$execution;Report=$capture.Report}
    }
    $baseline=& $runCases (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/engine-tests/QuietCli.Engine.Tests.dll')
    Write-WorkspaceJson (Join-Path $RunDirectory 'compiled-baseline.json') $baseline
    if($baseline.Execution.Outcome -ne 'Success' -or $baseline.Report.Failed){throw 'ConfigurationDeliveryEngineBaselineFailed'}
    $outcomes=[Collections.Generic.List[object]]::new();$passed=$baseline.Report.Passed;$failed=0;$catalogueCount=0
    if($Mutation){
        $catalogue=@(
            @{Name='yaml-size-limit';File='ConfigurationYaml.cs';From='if (count > 65536)';To='if (false)'},
            @{Name='yaml-inert-tags';File='ConfigurationYaml.cs';From='if (value != null && value.GetType().GetProperty("IsEmpty")?.GetValue(value) is false)';To='if (false)'},
            @{Name='delivery-initial-profile';File='MeasurementStore.cs';From='ON CONFLICT(id) DO NOTHING';To='ON CONFLICT(id) DO UPDATE SET payload=excluded.payload'},
            @{Name='token-conflict-transaction';File='MeasurementStore.cs';From='if ((long)stored["output_tokens"] != token.OutputTokens)';To='if (false)'},
            @{Name='configuration-budget-range';File='ConfigurationSchema.cs';From='|| number < rule.Min ||';To='|| false ||'},
            @{Name='delivery-receipt-dedup';File='Cmdlets/DeliveryCommands.cs';From='bool already = receipts.ContainsKey(fingerprint);';To='bool already = false;'},
            @{Name='delivery-token-count';File='Cmdlets/DeliveryCommands.cs';From='(long)count(text)';To='0L'},
            @{Name='delivery-reduction-bytes';File='Cmdlets/DeliveryCommands.cs';From='MeasurementTelemetry.Reduction(sources is IDictionary sourceMap ? sourceMap.Values : (IEnumerable)(sources ?? Array.Empty<object>()), completeness!, size, MetadataAdapter.Instance)';To='(long?)0L'},
            @{Name='delivery-surrogate-guard';File='QuietProjection.cs';From='char.IsHighSurrogate(text[limit - 1])';To='false'},
            @{Name='delivery-dictionary-bound';File='QuietProjection.cs';From='if (count++ >= maxItems) { state.Omitted += map.Count - maxItems; break; }';To='if (false) { }'},
            @{Name='script-escape-ascii-only';File='Cmdlets/ScriptCommands.cs';From='CodeGeneration.EscapeSingleQuotedStringContent(text)';To='text.Replace("''", "''''")'},
            @{Name='script-escape-none';File='Cmdlets/ScriptCommands.cs';From='CodeGeneration.EscapeSingleQuotedStringContent(text)';To='text'},
            @{Name='script-cycle-guard';File='Cmdlets/ScriptCommands.cs';From='if (ReferenceEquals(ancestor, value)) throw';To='if (false) throw'},
            @{Name='script-character-budget';File='Cmdlets/ScriptCommands.cs';From='budget.Characters > MaximumCharacters';To='false'},
            @{Name='script-node-budget';File='Cmdlets/ScriptCommands.cs';From='depth > MaximumDepth || budget.Nodes > MaximumNodes';To='depth > MaximumDepth'},
            @{Name='script-no-overwrite';File='Cmdlets/ScriptCommands.cs';From='if (File.Exists(path) || Directory.Exists(path)) throw';To='if (false) throw'},
            @{Name='script-link-rejected';File='Cmdlets/ScriptCommands.cs';From='if (PathGuard.HasLinkedAncestor(path)) throw new InvalidOperationException("QuietScriptLinkRejected");';To=''},
            @{Name='pathguard-reparse-bit';File='PathGuard.cs';From='(found & FileAttributes.ReparsePoint) != 0';To='false'},
            @{Name='input-path-link-rejected';File='Cmdlets/RuntimeCommands.cs';From='if (PathGuard.HasLinkedAncestor(inputPath)) throw new InvalidOperationException("QuietInputPathLinkRejected");';To=''},
            @{Name='script-callback-required';File='Cmdlets/ScriptCommands.cs';From='if (!request.ContainsKey("Output") && !request.ContainsKey("Complete"))';To='if (false)'},
            @{Name='script-recall-options';File='Cmdlets/ScriptCommands.cs';From='new("Recall|^(SaveRecall';To='new("^(SaveRecall'},
            @{Name='factory-isolation';File='Cmdlets/InvocationCommands.cs';From='var copy = (Hashtable)request.Clone();';To='var copy = request;'},
            @{Name='factory-cardinality';File='Cmdlets/InvocationCommands.cs';From='if (values.Count != 1) throw';To='if (false) throw'},
            @{Name='replay-partial-guard';File='Cmdlets/RecallReplayCommands.cs';From='if (!capture.CaptureComplete && !options.AllowPartial) throw';To='if (false) throw'},
            @{Name='replay-callback-required';File='Cmdlets/RecallReplayCommands.cs';From='if (options.Output is null && options.Complete is null) throw';To='if (false) throw'},
            @{Name='replay-gap-reset';File='Cmdlets/RecallReplayCommands.cs';From='if (evt.ObservedOffset != cursor)';To='if (false)'},
            @{Name='replay-tail-reset';File='Cmdlets/RecallReplayCommands.cs';From='if (cursor == capture.ReceivedBytes) runtime.CompleteStreams(); else DisposeStreams(runtime);';To='runtime.CompleteStreams();'},
            @{Name='replay-depth-restore';File='Cmdlets/RecallReplayCommands.cs';From='QuietCallState.RecallDepth--;';To=';'},
            @{Name='replay-projection';File='Cmdlets/RecallReplayCommands.cs';From='if (options.Projection is not null) request["Projection"] = options.Projection;';To='if (false) request["Projection"] = options.Projection;'},
            @{Name='replay-delimiter-clear';File='Cmdlets/RecallReplayCommands.cs';From='if (string.IsNullOrEmpty(options.RecordDelimiter)) request.Remove("RecordDelimiter"); else';To='if (false) request.Remove("RecordDelimiter"); else'},
            @{Name='replay-budget-range';File='Cmdlets/RecallReplayCommands.cs';From='parsed < 1 || parsed > int.MaxValue';To='parsed > int.MaxValue'},
            @{Name='replay-source-completeness';File='Cmdlets/RecallReplayCommands.cs';From='["Source"] = capture.SourceComplete && capture.CaptureComplete && readComplete';To='["Source"] = capture.SourceComplete && readComplete'},
            @{Name='replay-routing';File='Cmdlets/InvocationCommands.cs';From='if (original.ContainsKey("RecallId")) return RunSavedRecall(original);';To='if (false) return RunSavedRecall(original);'},
            @{Name='gain-from-overrides-days';File='Cmdlets/GainCommands.cs';From='if (lower is null && days is { } length)';To='if (days is { } length)'},
            @{Name='gain-days-end';File='Cmdlets/GainCommands.cs';From='upper ??= now;';To='upper = now;'},
            @{Name='gain-formats-exclusive';File='Cmdlets/GainCommands.cs';From='+ (AsJson ? 1 : 0) > 1)';To='+ (AsJson ? 1 : 0) > 2)'},
            @{Name='gain-compress-requires-json';File='Cmdlets/GainCommands.cs';From='bound.ContainsKey("Compress") && !AsJson';To='false'},
            @{Name='gain-time-range';File='Cmdlets/GainCommands.cs';From='low >= high';To='low > high'},
            @{Name='gain-unbounded-lower';File='Cmdlets/GainCommands.cs';From='?? MinimumMilliseconds';To='?? 0L'},
            @{Name='gain-poll-action';File='Cmdlets/GainCommands.cs';From='["Action"] = "gain-poll"';To='["Action"] = "gain-next"'},
            @{Name='gain-release-completed';File='Cmdlets/GainCommands.cs';From='{ reportId = null; break; }';To='{ break; }'},
            @{Name='gain-release-lost';File='Cmdlets/GainCommands.cs';From='reportId = next;';To='_ = next;'},
            @{Name='gain-first-report';File='Cmdlets/GainCommands.cs';From='report ??= Members.Get(response, "Report");';To='report = Members.Get(response, "Report");'},
            @{Name='gain-empty-session';File='Cmdlets/GainCommands.cs';From='!string.IsNullOrEmpty(SessionId)';To='SessionId is not null'},
            @{Name='gain-yaml-array';File='Cmdlets/GainCommands.cs';From='items[index] = YamlGraph(array.GetValue(index));';To='items[index] = array.GetValue(index);'},
            @{Name='scrub-confirmed';File='Cmdlets/GainCommands.cs';From='["Confirmed"] = true';To='["Confirmed"] = false'},
            @{Name='scrub-whatif';File='Cmdlets/GainCommands.cs';From='if (ShouldProcess(database, ';To='if (true || ShouldProcess(database, '},
            @{Name='agent-ref-start-count';File='Agents/AgentReferenceBlock.cs';From='startCount != 1 ||';To='false ||'},
            @{Name='agent-ref-end-count';File='Agents/AgentReferenceBlock.cs';From='endCount != 1 ||';To='false ||'},
            @{Name='agent-ref-order';File='Agents/AgentReferenceBlock.cs';From=' || start >= end';To=''},
            @{Name='agent-ref-tail-lost';File='Agents/AgentReferenceBlock.cs';From='text.AsSpan(end + End.Length)';To='""'},
            @{Name='agent-ref-injection';File='Agents/AgentReferenceBlock.cs';From='if (UnsafeReference.IsMatch(reference)) throw new InvalidOperationException("AgentInstructionReferenceInvalid");';To=''},
            @{Name='agent-ref-backslash';File='Agents/AgentReferenceBlock.cs';From='.Replace("\\", "%5C")';To=''},
            @{Name='agent-ref-percent';File='Agents/AgentReferenceBlock.cs';From='.Replace("%", "%25")';To=''},
            @{Name='agent-ref-replace-existing';File='Agents/AgentReferenceBlock.cs';From='if (startCount == 1) return';To='if (false) return'},
            @{Name='agent-write-conflict';File='Agents/AgentDocuments.cs';From='string.Equals(path, guarded, comparison)';To='false'},
            @{Name='agent-write-link';File='Agents/AgentDocuments.cs';From='(found & FileAttributes.ReparsePoint) != 0';To='false'},
            @{Name='agent-write-ancestor';File='Agents/AgentDocuments.cs';From='(found & FileAttributes.Directory) == 0 && current != path';To='false'},
            @{Name='agent-install-unchanged';File='Agents/AgentInstaller.cs';From='exists && content == text';To='false'},
            @{Name='agent-install-declined';File='Agents/AgentInstaller.cs';From='else if (declined) status';To='else if (false) status'},
            @{Name='agent-install-bom-strict';File='Agents/AgentDocuments.cs';From='new(false, true)';To='new(false, false)'},
            @{Name='scaffold-no-overwrite';File='Scaffolding/ModuleScaffold.cs';From='if (Path.Exists(target) || Path.Exists(tests))';To='if (false)'},
            @{Name='scaffold-tests-name';File='Scaffolding/ModuleScaffold.cs';From='name[..^".PoSh".Length] + ".Tests.PoSh"';To='name + ".Tests"'},
            @{Name='module-session-identity';File='QuietSession.cs';From='ModuleName = moduleName;';To='ModuleName = "QuietCli";'},
            @{Name='module-session-validation';File='QuietSession.cs';From='if (!System.Text.RegularExpressions.Regex.IsMatch(moduleName,';To='if (false && !System.Text.RegularExpressions.Regex.IsMatch(moduleName,'},
            @{Name='script-module-identity';File='Cmdlets/ScriptCommands.cs';From='Prologue.Replace("__QUIET_MODULE__", QuietSession.ModuleName, StringComparison.Ordinal)';To='Prologue.Replace("__QUIET_MODULE__", "QuietCli", StringComparison.Ordinal)'},
            @{Name='scaffold-module-identity';File='Scaffolding/ModuleScaffold.cs';From='[(QuietSession.ModuleName, "0.2.0")]';To='[("FrenchExDev2.QuietCli.Core.PoSh", "0.2.0")]'},
            @{Name='emit-events-not-recorded';File='Cmdlets/RuntimeCommands.cs';From='Events.Add(value);';To='_ = value;'},
            @{Name='emit-listener-not-disabled-after-failure';File='Cmdlets/RuntimeCommands.cs';From='(disabledListeners ??= []).Add(i);';To=';'},
            @{Name='emit-listener-skip-check-removed';File='Cmdlets/RuntimeCommands.cs';From='if (disabledListeners?.Contains(i) == true) continue;';To='if (false) continue;'},
            @{Name='emit-nested-inherits-listeners';File='Cmdlets/RuntimeCommands.cs';From='runtime.Listeners = request.ContainsKey("Listeners") ? QuietRuntime.NormalizeListeners(request["Listeners"]) : [];';To='runtime.Listeners = parent?.Listeners ?? (request.ContainsKey("Listeners") ? QuietRuntime.NormalizeListeners(request["Listeners"]) : []);'},
            @{Name='emit-listener-array-item-not-validated';File='Cmdlets/RuntimeCommands.cs';From='Select(item => Unwrap(item) as ScriptBlock ?? throw new InvalidOperationException("ListenerMustBeScriptBlock")).ToArray();';To='Select(item => Unwrap(item) as ScriptBlock).ToArray()!;'},
            @{Name='maxlines-requires-ui-guard-removed';File='Cmdlets/ArgumentCommands.cs';From='if (request.ContainsKey("MaxLines") && !Flag(request, "UI")) throw new InvalidOperationException("MaxLinesRequiresUI");';To=';'},
            @{Name='maxlines-nonpositive-silently-coerced';File='Cmdlets/RuntimeCommands.cs';From='if (maxLines <= 0) throw new InvalidOperationException("MaxLinesMustBePositive");';To='maxLines = Math.Max(1, maxLines);'},
            @{Name='ui-tail-fifo-head-not-advanced';File='Cmdlets/UiRenderer.cs';From='lane.Head = (lane.Head + 1) % lane.Tail.Length;';To='lane.Head = 0;'},
            @{Name='ui-tail-count-not-capped';File='Cmdlets/UiRenderer.cs';From='if (lane.Count < lane.Tail.Length) lane.Count++;';To='lane.Count++;'},
            @{Name='ui-lane-order-not-insertion';File='Cmdlets/UiRenderer.cs';From='laneOrder.Add(key);';To='laneOrder.Insert(0, key);'},
            @{Name='ui-format-machine-prefix-always-shown';File='Cmdlets/UiRenderer.cs';From='string machinePart = machine is { Length: > 0 } && !string.Equals(machine, laneKey, StringComparison.Ordinal) ? $"[{machine}]" : "";';To='string machinePart = machine is { Length: > 0 } ? $"[{machine}]" : "";'},
            @{Name='splat-value-options-lost';File='Cmdlets/ArgumentCommands.cs';From='request[option] = args[index];';To='request[option] = match.Success ? null : args[index];'},
            @{Name='event-delivery-not-projected';File='Cmdlets/DeliveryCommands.cs';From='["Events"] = safeEvents';To='["Events"] = null'},
            @{Name='ui-final-frame-omitted';File='Cmdlets/UiRenderer.cs';From='if (!failed) DrawFrame();';To=';'},
            @{Name='ui-viewport-height-ignored';File='Cmdlets/UiFrameLayout.cs';From='height = Math.Max(1, height);';To='height = 10000;'},
            @{Name='ui-viewport-width-ignored';File='Cmdlets/UiFrameLayout.cs';From='if (clean.GetCellWidth() <= width) return clean;';To='return clean;'},
            @{Name='ui-viewport-task-identity-lost';File='Cmdlets/UiFrameLayout.cs';From=' T:{Fit(task, width - 5 - projectWidth)}';To=' {Fit(task, width - 5 - projectWidth)}'}
        )
        $catalogueCount=$catalogue.Count
        if($MutationName.Count){
            foreach($name in $MutationName){if($name -cnotin $catalogue.Name){throw ('UnknownConfigurationDeliveryMutant: '+$name)}}
            $catalogue=@($catalogue|Where-Object {$_.Name -cin $MutationName})
        }
        foreach($mutant in $catalogue){
            if($OnProgress){& $OnProgress ('C# mutation: '+$mutant.Name) 'Running' $passed $failed}
            $directory=Join-Path $RunDirectory ('mutations/'+$mutant.Name)
            [void][IO.Directory]::CreateDirectory($directory)
            foreach($relative in @('FrenchExDev2.QuietCli.Core.PoSh/engine','FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests','FrenchExDev2.QuietCli.Core.Tests.PoSh/recall-tools')){
                foreach($file in Get-QuietSourceFiles (Join-Path $WorkspaceRoot $relative)){
                    $destination=Join-Path $directory ($relative+'/'+$file.Path)
                    [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($destination))
                    [IO.File]::Copy((Join-Path $WorkspaceRoot ($relative+'/'+$file.Path)),$destination)
                }
            }
            foreach($relative in @('global.json','Directory.Packages.props','FrenchExDev2.QuietCli.Core.PoSh/protocol.json')){[IO.File]::Copy((Join-Path $WorkspaceRoot $relative),(Join-Path $directory $relative))}
            $path=Join-Path $directory ('FrenchExDev2.QuietCli.Core.PoSh/engine/'+$mutant.File)
            $source=[IO.File]::ReadAllTextAsync($path,[Text.Encoding]::UTF8).GetAwaiter().GetResult()
            if(([regex]::Matches($source,[regex]::Escape($mutant.From))).Count -ne 1){throw ('ConfigurationDeliveryMutationAnchorInvalid: '+$mutant.Name)}
            [void][IO.File]::WriteAllTextAsync($path,$source.Replace($mutant.From,$mutant.To),[Text.UTF8Encoding]::new($false)).GetAwaiter().GetResult()
            $build=Invoke-CiProcess -FilePath dotnet -ArgumentList @('build',(Join-Path $directory 'FrenchExDev2.QuietCli.Core.Tests.PoSh/engine-tests/QuietCli.Engine.Tests.csproj'),'-f','net11.0','-c','Release','-o',(Join-Path $directory 'out'),'--nologo') -WorkingDirectory $directory -TimeoutSeconds 120
            if($build.Outcome -ne 'Success'){throw ('InvalidConfigurationDeliveryMutant: '+$mutant.Name)}
            $run=& $runCases (Join-Path $directory 'out/QuietCli.Engine.Tests.dll')
            $outcome=if($run.Execution.Outcome -eq 'Failed' -and $run.Report.Failed -gt 0){'Killed'}elseif($run.Execution.Outcome -eq 'Success' -and !$run.Report.Failed){'Survived'}else{'InfrastructureFailure'}
            $result=@{Name=$mutant.Name;State=$outcome;Run=$run;SourceSHA256=(Get-FileHash $path -Algorithm SHA256).Hash}
            Write-WorkspaceJson (Join-Path $directory 'result.json') $result;$outcomes.Add($result)
            if($outcome -eq 'Killed'){$passed++}else{$failed++}
        }
    }
    return [pscustomobject]@{Passed=$passed;Failed=$failed;Baseline=$baseline.Report;CatalogueCount=$catalogueCount;FullCatalogue=([bool]$Mutation -and !$MutationName.Count);Mutations=$outcomes.ToArray()}
}
