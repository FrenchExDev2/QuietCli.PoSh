$workspaceHelpers=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/lib/Common.psm1'
if(Test-Path -LiteralPath $workspaceHelpers){Import-Module $workspaceHelpers -DisableNameChecking -ErrorAction Stop}
. (Join-Path $PSScriptRoot 'Script.Tests.ps1')
. (Join-Path $PSScriptRoot 'Configuration.TestSupport.ps1')
. (Join-Path $PSScriptRoot 'Recall.Large.Tests.ps1')
. (Join-Path $PSScriptRoot 'Recall.Rtk.ps1')
. (Join-Path $PSScriptRoot 'Recall.Tools.ps1')
. (Join-Path $PSScriptRoot 'Recall.Tests.ps1')
. (Join-Path $PSScriptRoot 'ReportPaths.Tests.ps1')
. (Join-Path $PSScriptRoot 'CiDiagnostics.Tests.ps1')
. (Join-Path $PSScriptRoot 'GitHubCi.Tests.ps1')
. (Join-Path $PSScriptRoot 'CiCompanions.Tests.ps1')
. (Join-Path $PSScriptRoot 'CiOptimization.Tests.ps1')
. (Join-Path $PSScriptRoot 'CiScalability.Tests.ps1')
. (Join-Path $PSScriptRoot 'TestCaseMetadata.Tests.ps1')
. (Join-Path $PSScriptRoot 'TestCaseScheduling.Tests.ps1')
$caseMetadataLibrary=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/lib/TestCaseMetadata.psm1'
if(Test-Path -LiteralPath $caseMetadataLibrary){Import-Module $caseMetadataLibrary -ErrorAction Stop}
$caseSchedulingLibrary=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/lib/TestCaseScheduling.psm1'
if(Test-Path -LiteralPath $caseSchedulingLibrary){Import-Module $caseSchedulingLibrary -ErrorAction Stop}
. (Join-Path $PSScriptRoot 'ReadyToRun.Tests.ps1')
. (Join-Path $PSScriptRoot 'AutomationContracts.Tests.ps1')
. (Join-Path $PSScriptRoot 'EnvFile.Tests.ps1')
. (Join-Path $PSScriptRoot 'PullRequestUpdates.Tests.ps1')
. (Join-Path $PSScriptRoot 'DevelopmentWorkstation.Tests.ps1')
. (Join-Path $PSScriptRoot 'Emit.Tests.ps1')
. (Join-Path $PSScriptRoot 'WorkspaceProjects.Tests.ps1')
. (Join-Path $PSScriptRoot 'CommitWorkspace.Tests.ps1')
. (Join-Path $PSScriptRoot 'RuntimeDiagnosis.Tests.ps1')
. (Join-Path $PSScriptRoot 'CiImageRecipe.Tests.ps1')
. (Join-Path $PSScriptRoot 'WorkstationResources.Tests.ps1')
. (Join-Path $PSScriptRoot 'EditorExtensions.Tests.ps1')
#requires -Version 7.6
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'Performance.Tests.ps1')
. (Join-Path $PSScriptRoot 'Import.Tests.ps1')
. (Join-Path $PSScriptRoot 'Status.Aggregation.ps1')
. (Join-Path $PSScriptRoot 'Status.Controlled.Tests.ps1')
. (Join-Path $PSScriptRoot 'Integration.Gate.Tests.ps1')
. (Join-Path $PSScriptRoot 'Evidence.Tests.ps1')
. (Join-Path $PSScriptRoot 'HostMatrix.Tests.ps1')
. (Join-Path $PSScriptRoot 'PowerShellReleases.Tests.ps1')
. (Join-Path $PSScriptRoot 'SecondPass.Tests.ps1')
. (Join-Path $PSScriptRoot 'Control.Tests.ps1')
. (Join-Path $PSScriptRoot 'CoreMigration.Tests.ps1')
. (Join-Path $PSScriptRoot 'ConfigurationDelivery.Tests.ps1')
. (Join-Path $PSScriptRoot 'AgentInstructions.Tests.ps1')
function Assert-QuietEqual {
    <#
.SYNOPSIS
Asserts an independently known expected value with an actionable failure.
    .PARAMETER Actual
    Observed value.
    .PARAMETER Expected
    Independent expectation.
    .PARAMETER Because
    Invariant being checked.
    #>
    param([AllowNull()]$Actual,[AllowNull()]$Expected,[string]$Because='Values must match')
    if($Actual -cne $Expected){throw "$Because : expected <$Expected>, observed <$Actual>"}
}
function Invoke-QuietConformance {
    <#
.SYNOPSIS
Checks the shared envelope invariants without serializing business values.
    .PARAMETER Result
    Result returned by a candidate handler.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)]$Result)
    Assert-QuietEqual $Result.PSObject.TypeNames[0] 'QuietCli2.Result'
    Assert-QuietEqual $Result.Execution.State 'Finalized'
    Assert-QuietEqual $Result.Measurement.OutputBytes $null 'AsObject must not invent a serialized size'
    Assert-QuietEqual $Result.Deliveries.Count 0 'AsObject must not serialize a delivery'
    foreach($source in $Result.Internal.Sources.Values){if($source.Contains('Capture') -or $source.Contains('Stdout') -or $source.Contains('Stderr')){throw 'Raw native output retained in source metadata'}}
}
function Invoke-QuietCoreTests {
    <#
.SYNOPSIS
Executes independent native byte and object invariants in a companion module.
    .PARAMETER OnProgress
    Callback receiving name, state, passed and failed counters.
    .PARAMETER WorkspaceRoot
    Workspace containing the engine and independent fixture.
    .PARAMETER RunDirectory
    Existing shared report directory, including mandatory controlled fixture evidence.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[scriptblock]$OnProgress,[string]$RunDirectory)
    if(!$RunDirectory){
        Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/ReportPaths.psm1') -DisableNameChecking -ErrorAction Stop
        $RunDirectory=Join-Path (Get-QuietReportRoot $WorkspaceRoot 'integration') ([guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($RunDirectory)
    }
    $integration=[Collections.Generic.List[object]]::new()
    $fixture=Join-Path $PSScriptRoot 'lib/fixture/QuietCli.Fixture.dll'
    if(!(Test-Path -LiteralPath $fixture)){throw 'Build the independent C# fixture first.'}
    $dotnet=(Get-Command dotnet -CommandType Application|Select-Object -First 1).Source
    $performance=[Collections.Generic.List[object]]::new()
    $galleryEvidence=[Collections.Generic.List[object]]::new()
    $testScope=@{TtyExcluded=0}
    $cases=[ordered]@{}

    $cases['native Emit listeners preserve Unicode order and bounded JSON/YAML deliveries']={Test-QuietEmitListeners -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory}

    $cases['configuration and unique tokenized deliveries preserve their contracts']={
        $configuration=Invoke-QuietConfigurationDeliveryTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        if($configuration.Failed){throw ($configuration.Cases|Where-Object State -EQ Failed|ConvertTo-Json -Depth 8 -Compress)}
    }
    $cases['reusable scripts, factories and literal property regressions']={
        $scriptTests=Invoke-QuietScriptTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        if($scriptTests.Failed){throw ($scriptTests.Cases|Where-Object State -EQ Failed|ConvertTo-Json -Depth 8 -Compress)}
    }
    $cases['Recall capture and offline analysis regressions']={
        $recall=Invoke-QuietRecallTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        $testScope.TtyExcluded+=$recall.TtyExcluded
        if($recall.Failed){throw ($recall.Cases|Where-Object State -EQ Failed|ConvertTo-Json -Depth 12 -Compress)}
    }
    $cases['protocol configuration preserves bounds using host .NET APIs']={
        $performance.Add((& (Get-Module FrenchExDev2.QuietCli.Core.PoSh) {
            param($tests,$workspace)
            . $tests
            Test-QuietProtocolSpecification -WorkspaceRoot $workspace
        } (Join-Path $PSScriptRoot 'ProtocolSpecification.Tests.ps1') $WorkspaceRoot))
    }
    $cases['direct status callbacks preserve generated Unicode record digests']={$performance.Add((Test-QuietStatusAggregation))}
    $cases['fresh sessions measure inert Core import against a paired baseline']={$performance.Add((Invoke-QuietImportIntegration -WorkspaceRoot $WorkspaceRoot))}

    $cases['import diagnostics retain independent first-use controls']={$performance.Add((Invoke-QuietImportDiagnostics -WorkspaceRoot $WorkspaceRoot))}
    $cases['owned complex repositories use only Core callbacks and exact state oracles']={$integration.Add((Invoke-QuietControlledStatusIntegration -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory))}

    $cases['Core migration preserves metadata and compares local helper costs']={foreach($sample in Measure-QuietCoreMigration -Dotnet $dotnet){$performance.Add($sample)}}
    $cases['typed controls preserve duplex bytes and request rejection in both hosts']={Test-QuietTypedControls -Fixture $fixture -Dotnet $dotnet}
    $cases['typed controls measure local JSON avoidance with identical stdin']={foreach($sample in Measure-QuietTypedControls -Fixture $fixture -Dotnet $dotnet){$performance.Add($sample)}}
    $cases['compiled text framing and gain reports preserve their contracts']={foreach($sample in Invoke-QuietSecondPassChecks -WorkspaceRoot $WorkspaceRoot){$performance.Add($sample)}}

    $cases['managed target follows the actual CLR including preview and future hosts']={
        $core=Get-Module FrenchExDev2.QuietCli.Core.PoSh
        & $core {
            foreach($major in @(10,11,12)){
                $target=Resolve-QuietManagedTarget -RuntimeMajor $major
                $expected=if($major -eq 10){'net10.0'}else{'net11.0'}
                if($target.Framework -cne $expected){throw 'ManagedRuntimeSelectionMismatch'}
            }
            $rejected=$false;try{$null=Resolve-QuietManagedTarget -RuntimeMajor 9}catch{$rejected=$true}
            if(!$rejected){throw 'IncompatibleHostAccepted'}
        }
        $identity=Get-QuietEngine
        if($identity.Mode -eq 'InProcess'){
            $expected=if([Environment]::Version.Major -ge 11){'.NETCoreApp,Version=v11.0'}else{'.NETCoreApp,Version=v10.0'}
            Assert-QuietEqual $identity.Engine.TargetFramework $expected
            Assert-QuietEqual $identity.Engine.ProcessId $PID
        }
    }
    $cases['compiled framing and direct engine measure local overhead independently']={
        foreach($sample in Measure-QuietLocalOverhead -Fixture $fixture -Dotnet $dotnet){$performance.Add($sample)}
    }

    $cases['explicit event collection compiled properties and targeted mutations']={
        . (Join-Path $PSScriptRoot ConfigurationDelivery.Mutation.ps1)
        $result=Invoke-QuietConfigurationDeliveryEngine -WorkspaceRoot $WorkspaceRoot -RunDirectory (Join-Path $RunDirectory event-collection) -Mutation -MutationName @('emit-events-not-recorded','emit-unrequested-recording') -OnProgress {param($name,$state,$passed,$failed)Write-Host ('Mutation: '+$name+'; state='+$state+'; assertions='+$passed+'; failures='+$failed)}
        Write-WorkspaceJson (Join-Path $RunDirectory event-collection/campaign.json) $result
        if($result.Failed){throw 'ExplicitEventCollectionMutationFailed'}
    }

    $cases['cold engine and warm block-size measurements retain no business output']={
        Stop-QuietEngine
        $cold=[Diagnostics.Stopwatch]::StartNew();$identity=Get-QuietEngine;$cold.Stop()
        $performance.Add(@{Kind='ColdEngine';Milliseconds=$cold.Elapsed.TotalMilliseconds;Runtime=$identity.Engine.Runtime})
        foreach($size in @(4096,16384)){
            $before=Get-QuietEngine;$watch=[Diagnostics.Stopwatch]::StartNew()
            $r=quiet -AsObject -Role Infrastructure -ReadBlockBytes $size -StdoutMode Bytes -Output {param($e,$r)} $dotnet $fixture emit 8388608
            $elapsed=$watch.Elapsed.TotalMilliseconds;$after=Get-QuietEngine
            Assert-QuietEqual $r.Outcome Success
            Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 8388608
            $performance.Add(@{Kind='WarmStream';ReadBlockBytes=$size;Bytes=8388608;ElapsedMs=$elapsed;NativeMs=$r.Execution.Native.ElapsedMs;CallbackMs=$r.Execution.CallbackMs;ProtocolBytes=($after.ProtocolInputBytes+$after.ProtocolOutputBytes-$before.ProtocolInputBytes-$before.ProtocolOutputBytes);ProtocolRequests=$after.Requests-$before.Requests;Interpretation='One fixture sample, not a general speed claim.'})
        }
    }

    $cases['C# protocol and concurrent SQLite assertions']={
        $assembly=Join-Path $PSScriptRoot 'lib/engine-tests/QuietCli.Engine.Tests.dll'
        $nativeDirectory=Join-Path $WorkspaceRoot ('FrenchExDev2.QuietCli.Core.PoSh/resources/runtime/runtimes/'+[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier+'/native')
        $r=quiet -AsObject -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} $dotnet $assembly $nativeDirectory
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Passed 67
        Assert-QuietEqual $r.Data.Failed 0
    }
    $cases['PTY reports a merged terminal counter without fake stderr separation']={
        $r=quiet -AsObject -Transport Pty -Data @{Seen=0L;Text=[Text.StringBuilder]::new()} -Output {param($e,$r)$r.Data.Seen+=$e.ByteCount;[void]$r.Data.Text.Append($e.Text)} $dotnet $fixture terminal
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead $null
        Assert-QuietEqual $r.Execution.Native.StderrBytesRead $null
        Assert-QuietEqual $r.Execution.Native.TerminalBytesRead $r.Data.Seen
        if(!$r.Data.Text.ToString().Contains('out') -or !$r.Data.Text.ToString().Contains('err')){throw 'PTY lost stdout or stderr'}
    }
    $cases['exact stdout/stderr counters with no capture']={
        $r=quiet -AsObject -StdoutMode Bytes -StderrMode Bytes -Data @{Seen=0L} -Output {param($e,$r)$r.Data.Seen+=$e.Bytes.Length} $dotnet $fixture mixed 123456 234567
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 123456
        Assert-QuietEqual $r.Execution.Native.StderrBytesRead 234567
        Assert-QuietEqual $r.Data.Seen 358023
        Invoke-QuietConformance $r
    }
    $cases['AsObject does not enumerate or serialize business getters']={
        $business=[pscustomobject]@{Marker='local'}
        $business|Add-Member ScriptProperty Forbidden {throw 'Business object was enumerated for measurements'}
        $r=quiet -AsObject -Data $business -Output {param($e,$r)} $dotnet $fixture emit 10
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual ([object]::ReferenceEquals($r.Data,$business)) $true
        Invoke-QuietConformance $r
    }
    $cases['large output retains only bounded transport blocks']={
        $before=[GC]::GetTotalMemory($true)
        $r=quiet -AsObject -StdoutMode Bytes -Output {param($e,$r)} $dotnet $fixture emit 67108864
        $after=[GC]::GetTotalMemory($true)
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 67108864
        if($after-$before -gt 33554432){throw 'Managed memory grew proportionally to discarded output'}
        Invoke-QuietConformance $r
    }
    $cases['nested callback inherits context without serializing child objects']={
        $r=quiet -AsObject -C nested -Data @{Child=$null} -Output {param($e,$r)if(!$r.Data.Child){$r.Data.Child=quiet -AsObject -Data @{Bytes=0L} -StdoutMode Bytes -Output {param($e,$r)$r.Data.Bytes+=$e.Bytes.Length} $dotnet $fixture emit 29}} $dotnet $fixture emit 17
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Child.Context nested
        Assert-QuietEqual $r.Data.Child.Data.Bytes 29
        Assert-QuietEqual $r.Execution.Children 1
        Assert-QuietEqual $r.Internal.Sources.Count 2
        Invoke-QuietConformance $r.Data.Child
    }
    $cases['assigned child failure remains visible']={
        $r=quiet -AsObject -Output {param($e,$r)$child=quiet -AsObject -Output {param($e,$r)} $dotnet $fixture fail} $dotnet $fixture emit 1
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Execution.Issues.Count 1
    }
    $cases['context is not sticky across independent invocations']={
        $named=quiet -AsObject -C named -Output {param($e,$r)} $dotnet $fixture emit 1
        $generic=quiet -AsObject -Output {param($e,$r)} $dotnet $fixture emit 1
        Assert-QuietEqual $named.Context named
        Assert-QuietEqual $generic.Context $null
    }
    $cases['stdin bytes are exact and output is drained while feeding']={
        $bytes=[byte[]]::new(1048576);[Random]::new(42).NextBytes($bytes)
        $r=quiet -AsObject -InputBytes $bytes -Data @{Hash=[Text.StringBuilder]::new()} -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Hash.Append($e.Text)}} -Complete {param($r) @{Hash=$r.Data.Hash.ToString()}} $dotnet $fixture hash
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Execution.Native.StdinBytesWritten $bytes.Length
        Assert-QuietEqual $r.Data.Hash ([Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)))
    }
    $cases['UTF8 and NUL framing preserve split Unicode characters']={
        $r=quiet -AsObject -RecordDelimiter ([string][char]0) -Data ([Collections.Generic.List[string]]::new()) -Output {param($e,$r)$r.Data.Add($e.Text)} $dotnet $fixture unicode
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Count 2
        Assert-QuietEqual $r.Data[0] 'é漢🙂'
        Assert-QuietEqual $r.Data[1] 'fin'
    }
    $cases['truncated UTF8 fails analysis rather than dropping bytes']={
        $r=quiet -AsObject -Output {param($e,$r)} $dotnet $fixture invalid
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Completeness.Analysis $false
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 1
    }
    $cases['Complete runs once after Output failure and native drain']={
        $state=@{Calls=0}
        $r=quiet -AsObject -State $state -Output {param($e,$r)throw 'expected parser failure'} -Complete {param($r)$r.State.Calls++} $dotnet $fixture emit 131072
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $state.Calls 1
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 131072
    }
    $cases['accidental Output emission never becomes business Data']={
        $r=quiet -AsObject -Data @{Kept=$true} -Output {param($e,$r)'accidental'} $dotnet $fixture emit 1
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Data.Kept $true
    }
    $cases['timeout preserves partial native state']={
        $r=quiet -AsObject -TimeoutSeconds 0.3 -Output {param($e,$r)} $dotnet $fixture hang
        Assert-QuietEqual $r.Outcome Timeout
        Assert-QuietEqual $r.Completeness.Source $false
    }
    $cases['interactive cancellation affects only the owned child']={
        $r=quiet -AsObject -Interaction {param($r)$r.Cancel()} -Output {param($e,$r)} $dotnet $fixture hang
        Assert-QuietEqual $r.Outcome Cancelled
        Assert-QuietEqual $r.Completeness.Source $false
    }
    $cases['delimiter overflow fails analysis and still drains bytes']={
        $r=quiet -AsObject -RecordDelimiter "`n" -MaxRecordBytes 64 -Output {param($e,$r)} $dotnet $fixture emit 20000
        Assert-QuietEqual $r.Outcome Failed
        Assert-QuietEqual $r.Completeness.Analysis $false
        Assert-QuietEqual $r.Execution.Native.StdoutBytesRead 20000
    }
    $cases['native arguments preserve empty strings spaces and Unicode']={
        $r=quiet -AsObject -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)[void]$r.Data.Append($e.Text)} -Complete {param($r),@($r.Data.ToString()|ConvertFrom-Json)} $dotnet $fixture args '' 'a b' 'é🙂' '--native'
        Assert-QuietEqual $r.Outcome Success
        Assert-QuietEqual $r.Data.Count 4
        Assert-QuietEqual $r.Data[0] ''
        Assert-QuietEqual $r.Data[2] 'é🙂'
    }
    $cases['delivery is bounded and AsObject remains unserialized until requested']={
        $r=quiet -AsObject -Data @{Values=@(1..100)} -Output {param($e,$r)} $dotnet $fixture emit 2000
        Assert-QuietEqual $r.Deliveries.Count 0
        $json=$r|ConvertTo-QuietJson -MaxItems 5 -MaxOutputBytes 1024
        $doc=$json|ConvertFrom-Json
        Assert-QuietEqual $doc.Data.Values.Count 5
        Assert-QuietEqual $doc.Truncation.Applied $true
        Assert-QuietEqual $r.Data.Values.Count 100
        Assert-QuietEqual $r.Measurement.OutputBytes ([Text.Encoding]::UTF8.GetByteCount($json))
        Assert-QuietEqual $r.Deliveries[0].Text $json
    }
    $cases['empty singleton and nested arrays preserve JSON shape']={
        $r=quiet -AsObject -Data @{Empty=@();One=@(7);Nested=@(@(1,2),@(3,4));Nothing=$null;Object=@{}} -Output {param($e,$r)} $dotnet $fixture emit 1
        $json=$r|ConvertTo-QuietJson
        $doc=$json|ConvertFrom-Json -AsHashtable
        Assert-QuietEqual ($doc.Data.Empty -is [array]) $true
        Assert-QuietEqual $doc.Data.Empty.Count 0
        Assert-QuietEqual $doc.Data.One.Count 1
        Assert-QuietEqual $doc.Data.Nested[0].Count 2
        Assert-QuietEqual $doc.Data.Nothing $null
    }
    $cases['bounded delivery preserves failure identity without serializing omitted business data']={
        $r=quiet -AsObject -Data @{Large=('é'*5000)} -Output {param($e,$r)throw ('diagnostic '*1000)} $dotnet $fixture emit 10
        $json=$r|ConvertTo-QuietJson -MaxOutputBytes 300
        $document=$json|ConvertFrom-Json
        Assert-QuietEqual $document.Outcome Failed
        Assert-QuietEqual $document.Error.Code OutputCallbackFailed
        Assert-QuietEqual $document.Truncation.Applied $true
        if([Text.Encoding]::UTF8.GetByteCount($json) -gt 300){throw 'Failure envelope exceeded the final budget'}
    }
    $cases['generic and named gain filters are independent']={
        $named=Get-QuietCliGain -C named -AsObject
        $generic=Get-QuietCliGain -Generic -AsObject
        if($named.Invocations -lt 1 -or $generic.Invocations -lt 1){throw 'Expected persisted named and generic invocations'}
        Assert-QuietEqual $named.RootDeliveryBytes $null
    }
    $cases['delivery token count observes produced text only']={
        $r=quiet -AsObject -Data @{Message='évidence'} -Output {param($e,$r)} $dotnet $fixture emit 1
        Assert-QuietEqual $r.Measurement.OutputTokens $null
        $text=Out-QuietResult -InputObject $r -Tokenizer o200k_base
        if($r.Measurement.OutputTokens -le 0){throw 'Exact delivery tokenizer was not applied'}
        Assert-QuietEqual $r.Measurement.NativeTokens $null
        Assert-QuietEqual $r.Measurement.OutputBytes ([Text.Encoding]::UTF8.GetByteCount($text))
    }
    $cases['production agent instructions preserve project rules and installed resources']={
        $agentReport=Invoke-QuietAgentInstructionTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory
        $integration.Add($agentReport)
        if($agentReport.Failed){throw ('AgentInstructionQualificationFailed: '+($agentReport.Cases|Where-Object State -EQ Failed|ConvertTo-Json -Compress))}
    }
    $cases['module scaffolding creates inert handlers and independent failing test companions']={
        $parent=Join-Path $WorkspaceRoot ('artifacts/scaffold-tests/'+[guid]::NewGuid().ToString('N'))
        $name='Sample.QuietTool.PoSh'
        $generated=New-QuietModule -Name $name -Binary quietfixture -OutputPath $parent
        $manifest=Import-PowerShellDataFile (Join-Path $generated.Module ($name+'.psd1'))
        Assert-QuietEqual $manifest.RequiredModules.Count 1
        Assert-QuietEqual $manifest.RequiredModules[0].ModuleName FrenchExDev2.QuietCli.Core.PoSh
        $testName='Sample.QuietTool.Tests.PoSh'
        $testManifest=Import-PowerShellDataFile (Join-Path $generated.Tests ($testName+'.psd1'))
        Assert-QuietEqual $testManifest.RequiredModules.Count 2
        $module=Import-Module (Join-Path $generated.Module ($name+'.psd1')) -PassThru
        try{
            $catalogue=@(Get-QuietHandler -Binary quietfixture)
            Assert-QuietEqual $catalogue.Count 1
            Assert-QuietEqual $catalogue[0].Qualification NotImplemented
            $errors=$null;$tokens=$null
            $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $generated.Tests ($testName+'.psm1')),[ref]$tokens,[ref]$errors)
            Assert-QuietEqual $errors.Count 0
            $function=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst]},$true)
            if(!$function.GetHelpContent()){throw 'Generated test entry point has no readable help'}
            $rejected=$false
            try{$null=New-QuietModule -Name $name -Binary quietfixture -OutputPath $parent}catch{$rejected=$_.Exception.Message -eq 'ModuleDestinationExists'}
            Assert-QuietEqual $rejected $true
        }finally{Remove-Module $module}
        Assert-QuietEqual @(Get-QuietHandler -Binary quietfixture).Count 0
        if(Get-Module FrenchExDev2.QuietCli.Git.PoSh){throw 'CoreScaffoldMustNotLoadGitCompanion'}
        $statusName='Sample.QuietStatus.PoSh'
        $statusModule=New-QuietModule -Name $statusName -Binary git -OutputPath $parent
        $handler=@'
Register-QuietHandler -Id 'Sample.QuietStatus.PoSh' -Definition @{
    Binary='git';ModuleVersion='0.1.0';VersionRange='fixture';Qualification='Synthetic'
    Probe={
        param($runtime)
        $r=quiet -AsObject -Role Probe -Data @{Version=''} -Output {param($e,$r)if($e.Stream -eq 'stdout'){$r.Data.Version+=$e.Text}} -Complete {param($r)$r.Data.Version} -FilePath $runtime.Request.FilePath -ArgumentList @('--version')
        if($r.Outcome -ne 'Success'){throw 'FixtureVersionProbeFailed'}
        $r.Data.Trim()
    }
    TestVersion={param($version)$version -match '^git version [0-9]+\.'}
    Match={param($request,$version)($request.ArgumentList -join '|') -ceq 'status|--porcelain=v1|-z'}
    Execute={
        param($runtime)
        $rows=[Collections.Generic.List[string]]::new()
        $r=quiet -AsObject -WorkingDirectory $runtime.Request.WorkingDirectory -Environment $runtime.Request.Environment -RecordDelimiter ([string][char]0) -Data $rows -Output {
            param($e,$r)
            if($e.Stream -eq 'stdout' -and $e.Text.Length){$r.Data.Add($e.Text)}
        } -Complete {param($r)[pscustomobject]@{Entries=$r.Data.ToArray();Count=$r.Data.Count}} -FilePath $runtime.Request.FilePath -ArgumentList $runtime.Request.ArgumentList
        if($r.Outcome -ne 'Success' -or !$r.Completeness.Source -or !$r.Completeness.Analysis){throw 'FixtureStatusIncomplete'}
        $r.Data
    }
}
'@
        [IO.File]::WriteAllText((Join-Path $statusModule.Module 'src/Handler.ps1'),$handler,[Text.UTF8Encoding]::new($false))
        $repo=Join-Path $parent 'status-repository';[void][IO.Directory]::CreateDirectory($repo)
        $gitEnvironment=@{GIT_CONFIG_NOSYSTEM='1';GIT_CONFIG_GLOBAL=(Join-Path $parent 'empty.gitconfig');GIT_CONFIG_COUNT='0'}
        $init=quiet -AsObject -WorkingDirectory $repo -Environment $gitEnvironment -Output {param($e,$r)} git init
        Assert-QuietEqual $init.Outcome Success
        $module=Import-Module (Join-Path $statusModule.Module ($statusName+'.psd1')) -PassThru
        try{
            $clean=quiet -AsObject -WorkingDirectory $repo -Environment $gitEnvironment git status --porcelain=v1 -z
            Invoke-QuietConformance $clean
            Assert-QuietEqual $clean.Outcome Success
            Assert-QuietEqual $clean.Data.Count 0
            [IO.File]::WriteAllText((Join-Path $repo 'é file 漢.txt'),'synthetic',[Text.UTF8Encoding]::new($false))
            $dirty=quiet -AsObject -WorkingDirectory $repo -Environment $gitEnvironment git status --porcelain=v1 -z
            Invoke-QuietConformance $dirty
            Assert-QuietEqual $dirty.Outcome Success
            Assert-QuietEqual $dirty.Completeness.Source $true
            Assert-QuietEqual $dirty.Completeness.Analysis $true
            Assert-QuietEqual $dirty.Data.Count 1
            Assert-QuietEqual $dirty.Data.Entries[0] '?? é file 漢.txt'
            if(Get-Module FrenchExDev2.QuietCli.Git.PoSh){throw 'CoreScaffoldImportedRealGitCompanion'}
        }finally{Remove-Module $module}
        Assert-QuietEqual @(Get-QuietHandler -Binary git).Count 0
    }

    $cases['security audit counterexamples are closed with independent evidence']={
        $run=Join-Path $WorkspaceRoot ('artifacts/security-regressions/'+[guid]::NewGuid().ToString('N'))
        $worker=Join-Path $PSScriptRoot 'audit/Invoke-AuditWorker.ps1'
        $r=quiet -AsObject -Role Infrastructure -TimeoutSeconds 120 -Data ([Text.StringBuilder]::new()) -Output {param($e,$r)if($e.Stream -eq 'stdout'){[void]$r.Data.Append($e.Text)}} -Complete {param($r)$r.Data.ToString()|ConvertFrom-Json} pwsh -File $worker -WorkspaceRoot $WorkspaceRoot -RunDirectory $run
        Assert-QuietEqual $r.Outcome Success ('Audit regression failed: '+$run)
        Assert-QuietEqual $r.Data.State Success
        Assert-QuietEqual $r.Data.Failed 0
    }

    $caseMetadata=@{
        'native Emit listeners preserve Unicode order and bounded JSON/YAML deliveries'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'configuration and unique tokenized deliveries preserve their contracts'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'reusable scripts, factories and literal property regressions'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'Recall capture and offline analysis regressions'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'protocol configuration preserves bounds using host .NET APIs'=@{TestKind='Integration';Dependencies=@('FileSystem','EngineState')}
        'direct status callbacks preserve generated Unicode record digests'=@{TestKind='Unit';Dependencies=@()}
        'fresh sessions measure inert Core import against a paired baseline'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'import diagnostics retain independent first-use controls'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'owned complex repositories use only Core callbacks and exact state oracles'=@{TestKind='Integration';Dependencies=@('FileSystem','GitProcess','NativeProcess','EngineState')}
        'Core migration preserves metadata and compares local helper costs'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'typed controls preserve duplex bytes and request rejection in both hosts'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'typed controls measure local JSON avoidance with identical stdin'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'compiled text framing and gain reports preserve their contracts'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'managed target follows the actual CLR including preview and future hosts'=@{TestKind='Integration';Dependencies=@('FileSystem','EngineState')}
        'compiled framing and direct engine measure local overhead independently'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'explicit event collection compiled properties and targeted mutations'=@{TestKind='Integration';Dependencies=@('FileSystem','DotNetBuild','NativeProcess')}
        'cold engine and warm block-size measurements retain no business output'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'C# protocol and concurrent SQLite assertions'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'PTY reports a merged terminal counter without fake stderr separation'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'exact stdout/stderr counters with no capture'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'AsObject does not enumerate or serialize business getters'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'large output retains only bounded transport blocks'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'nested callback inherits context without serializing child objects'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'assigned child failure remains visible'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'context is not sticky across independent invocations'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'stdin bytes are exact and output is drained while feeding'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'UTF8 and NUL framing preserve split Unicode characters'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'truncated UTF8 fails analysis rather than dropping bytes'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'Complete runs once after Output failure and native drain'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'accidental Output emission never becomes business Data'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'timeout preserves partial native state'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'interactive cancellation affects only the owned child'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'delimiter overflow fails analysis and still drains bytes'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'native arguments preserve empty strings spaces and Unicode'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'delivery is bounded and AsObject remains unserialized until requested'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'empty singleton and nested arrays preserve JSON shape'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'bounded delivery preserves failure identity without serializing omitted business data'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'generic and named gain filters are independent'=@{TestKind='Integration';Dependencies=@('FileSystem','EngineState')}
        'delivery token count observes produced text only'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'production agent instructions preserve project rules and installed resources'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'module scaffolding creates inert handlers and independent failing test companions'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess')}
        'security audit counterexamples are closed with independent evidence'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
    }
    Assert-QuietTestCaseMetadata -CaseNames @($cases.Keys) -Metadata $caseMetadata
    $passed=0;$failed=0;$results=[Collections.Generic.List[object]]::new()
    # Development-only selection (QUIETCLI_TEST_CASE wildcard, QUIETCLI_TEST_STOP_ON_FIRST_FAILURE=1); the default run executes every case.
    $casePattern=$env:QUIETCLI_TEST_CASE;$stopOnFirst=$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE -ceq '1'
    $stoppedAt=$null;$skipped=0;$ttyExcluded=0
    $selected=[Collections.Generic.List[string]]::new()
    foreach($entry in $cases.GetEnumerator()){
        if($env:QUIETCLI_TEST_SKIP_TTY -ceq '1' -and $entry.Key -clike 'PTY *'){$ttyExcluded++;continue}
        if($casePattern -and $entry.Key -notlike $casePattern){$skipped++;continue}
        $selected.Add($entry.Key)
    }
    $policy=Get-QuietTestExecutionPolicy -ManifestPath (Join-Path $PSScriptRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -CaseNames @($cases.Keys)
    $budget=1
    if($env:QUIETCLI_TEST_MAX_CONCURRENCY -and (![int]::TryParse($env:QUIETCLI_TEST_MAX_CONCURRENCY,[ref]$budget) -or $budget -lt 1 -or $budget -gt 32)){throw 'TestMaxConcurrencyInvalid'}
    $caseWorker=$env:QUIETCLI_TEST_CASE_WORKER -ceq '1'
    $plan=Get-QuietTestExecutionPlan -CaseNames $selected.ToArray() -Policy $policy -MaxConcurrency $budget
    Write-WorkspaceJson (Join-Path $RunDirectory 'core-execution-plan.json') $plan
    $batches=[Collections.Generic.List[object]]::new()
    foreach($stage in $plan.Stages){
        if($stoppedAt){$skipped+=$stage.Cases.Count;continue}
        if($stage.Mode -ceq 'IsolatedProcess' -and !$caseWorker){
            $counts=@{Passed=$passed;Failed=$failed}
            $batch=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Cases $stage.Cases.ToArray() -MaxConcurrency $plan.MaxConcurrency -StopOnFirstFailure:$stopOnFirst -SkipTty:($env:QUIETCLI_TEST_SKIP_TTY -ceq '1') -ExpectedRuntimeIdentifier $env:QUIETCLI_TEST_EXPECT_RID -OnCase {
                param($name,$caseState,$caseResult)
                if($caseState -ceq 'Passed'){$counts.Passed++}elseif($caseState -ceq 'Failed'){$counts.Failed++}
                if($OnProgress){& $OnProgress ('['+$caseMetadata[$name].TestKind+'] '+$name) $caseState $counts.Passed $counts.Failed}
            }
            $passed=$counts.Passed;$failed=$counts.Failed
            foreach($item in $batch.Cases){
                $item|Add-Member NoteProperty TestKind $caseMetadata[$item.Name].TestKind
                $item|Add-Member NoteProperty Dependencies @($caseMetadata[$item.Name].Dependencies)
                $results.Add($item)
            }
            $skipped+=$batch.NotStarted.Count;$batches.Add($batch)
            if($stopOnFirst -and @($batch.Cases|Where-Object State -CEQ Failed).Count){$stoppedAt="stopped at case $($passed+$failed) of $($cases.Count)"}
            continue
        }
        foreach($plannedCase in $stage.Cases){
            if($stoppedAt){$skipped++;continue}
            $name=$plannedCase.Name;$metadata=$caseMetadata[$name]
            $progressName='['+$metadata.TestKind+'] '+$name
            if($OnProgress){& $OnProgress $progressName 'Running' $passed $failed}
            $failure=$null
            try{$null=& $cases[$name];$passed++;$state='Passed'}catch{$failed++;$state='Failed';$failure=$_.Exception.Message}
            $results.Add([pscustomobject]@{Name=$name;State=$state;Error=$failure;TestKind=$metadata.TestKind;Dependencies=@($metadata.Dependencies);ExecutionMode=if($caseWorker){'CaseWorker'}else{$plannedCase.Mode}})
            if($OnProgress){& $OnProgress $progressName $state $passed $failed}
            if($state -eq 'Failed' -and $stopOnFirst){$stoppedAt="stopped at case $($passed+$failed) of $($cases.Count)"}
        }
    }
    [pscustomobject]@{Project='FrenchExDev2.QuietCli.Core.PoSh';Passed=$passed;Failed=$failed;Partial=[bool]$casePattern;Incomplete=[bool]$stoppedAt;StoppedAt=$stoppedAt;Skipped=$skipped;TtyExcluded=($ttyExcluded+$testScope.TtyExcluded);Cases=$results.ToArray();Performance=$performance.ToArray();Gallery=$galleryEvidence.ToArray();Integration=$integration.ToArray();ExecutionPlan=$plan;ParallelBatches=$batches.ToArray()}
}
Export-ModuleMember -Function Invoke-QuietCoreTests,Assert-QuietEqual,Invoke-QuietConformance

Export-ModuleMember -Function Compare-QuietRecallAnalysis,Export-QuietRecallFixture,Reduce-QuietRecall,Invoke-QuietRecallTests

Export-ModuleMember -Function Invoke-QuietRecallRtkComparison

Export-ModuleMember -Function Invoke-QuietRecallLargeTests
