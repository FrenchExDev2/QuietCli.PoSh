foreach($library in @('TestCaseMetadata','TestCaseScheduling')){
    $path=Join-Path (Split-Path $PSScriptRoot -Parent) ('scripts/lib/'+$library+'.psm1')
    if(Test-Path -LiteralPath $path){Import-Module $path -ErrorAction Stop}
}
. (Join-Path $PSScriptRoot 'VagrantLine.Tests.ps1')
. (Join-Path $PSScriptRoot 'VagrantFuzz.Tests.ps1')
. (Join-Path $PSScriptRoot 'VagrantParser.Mutation.ps1')
. (Join-Path $PSScriptRoot '../FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1')
function Invoke-QuietVagrantTests {
    <#
    .SYNOPSIS
    Runs the Vagrant --machine-readable parser/engine suite: deterministic line cases, the shared
    up/provision engine against the fixture process, and the seeded fuzz campaign.
    .PARAMETER WorkspaceRoot
    QuietCli2 workspace root.
    .PARAMETER OnProgress
    Receives name, state, passed and failed counters.
    #>
    [CmdletBinding()]param([Parameter(Mandatory)][string]$WorkspaceRoot,[scriptblock]$OnProgress,[string]$RunDirectory)
    . (Join-Path $WorkspaceRoot 'scripts/Common.ps1')
    if (!$RunDirectory) { $RunDirectory = Join-Path (Get-QuietReportRoot $WorkspaceRoot 'tests') ([guid]::NewGuid().ToString('N')) }
    $root = Join-Path $RunDirectory 'vagrant-fixtures'
    [void][IO.Directory]::CreateDirectory($root)
    $RootDirectory = $root
    $dotnet = (Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
    $fixture = Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
    $cases = [ordered]@{}
    $lineCases = Get-QuietVagrantLineCases -RootDirectory $root -WorkspaceRoot $WorkspaceRoot
    foreach ($entry in $lineCases.GetEnumerator()) { $cases[$entry.Key] = $entry.Value }
    $fuzzCases = Get-QuietVagrantFuzzCases -RootDirectory $root -WorkspaceRoot $WorkspaceRoot
    foreach ($entry in $fuzzCases.GetEnumerator()) { $cases[$entry.Key] = $entry.Value }
    if ($env:QUIETCLI_VAGRANT_PARSER_MUTATION -eq '1') {
        $cases['Vagrant parser PowerShell-source mutants are detected'] = {
            $mutationRoot = Join-Path $root 'mutation-run'
            [void][IO.Directory]::CreateDirectory($mutationRoot)
            $summary = Invoke-QuietVagrantParserMutation -WorkspaceRoot $WorkspaceRoot -RunDirectory $mutationRoot
            Write-WorkspaceJson (Join-Path $mutationRoot 'summary.json') $summary
            if ($summary.Failed -gt 0) {
                $offenders = ($summary.Cases | Where-Object { $_.Outcome -ne 'Killed' } | ForEach-Object { $_.Name + '=' + $_.Outcome }) -join ', '
                throw "Vagrant parser mutation campaign had survivors/infrastructure failures: $offenders"
            }
        }
    }
    $caseMetadata=@{
        'Vagrant parser PowerShell-source mutants are detected'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState');EnabledWhen='QUIETCLI_VAGRANT_PARSER_MUTATION=1'}
        'ConvertFrom-QuietVagrantMachineReadableLine matches the independent oracle on interleaved web/db lines'=@{TestKind='Unit';Dependencies=@()}
        'a ui/info Running provisioner line is recognized as the ProvisionerStarted trigger shape'=@{TestKind='Unit';Dependencies=@()}
        'real provisioner prefixes preserve exact machine identity across generated names and malformed messages'=@{TestKind='Unit';Dependencies=@()}
        'an escaped comma in Vagrant data is correctly un-escaped'=@{TestKind='Unit';Dependencies=@()}
        'a malformed or truncated line is dropped without throwing'=@{TestKind='Unit';Dependencies=@()}
        'Get-QuietVagrantProviderLabel reports docker by default and docker via podman when DOCKER_HOST points at a podman socket'=@{TestKind='Integration';Dependencies=@('ProcessEnvironment')}
        'Invoke-QuietVagrantMachineReadableRun emits one event per valid line, skips malformed ones, and sets the Ui header/lanes'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState','ProcessEnvironment')}
        'Invoke-QuietVagrantUp and Invoke-QuietVagrantProvision produce the same events/lanes from the same transcript'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        '--no-provision is purely the absence of the trigger line: zero ProvisionerStarted events, no special-casing'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'a silent machine keeps its last-written lane entry while another machine keeps advancing'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'registered Vagrant handlers deliver live events through the outer native pipeline and preserve failure visibility'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'bounded fuzz: random multi-machine --machine-readable transcripts survive arbitrary chunk fragmentation'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'bounded malformed timestamps and missing fields are rejected without partial events'=@{TestKind='Unit';Dependencies=@()}
    }
    $inventory=Get-QuietCompanionTestInventory -ManifestPath (Join-Path $PSScriptRoot 'FrenchExDev2.QuietCli.Vagrant.Tests.PoSh.psd1')
    Assert-QuietTestCaseMetadata -CaseNames $inventory.CaseNames -Metadata $caseMetadata
    $passed=0;$failed=0;$ttyExcluded=0;$skipped=0;$stoppedAt=$null;$results=[Collections.Generic.List[object]]::new()
    $selected=[Collections.Generic.List[string]]::new()
    $activeMetadata=Get-QuietActiveCaseMetadata -Metadata $caseMetadata
    Assert-QuietTestCaseMetadata -CaseNames @($cases.Keys) -Metadata $activeMetadata
    $pattern=$env:QUIETCLI_TEST_CASE;$stopOnFirst=$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE -ceq '1'
    foreach($name in $cases.Keys){
        if($env:QUIETCLI_TEST_SKIP_TTY -ceq '1' -and $name -clike 'PTY *'){$ttyExcluded++;continue}
        if($pattern -and $name -notlike $pattern){$skipped++;continue}
        $selected.Add($name)
    }
    $policy=Get-QuietTestExecutionPolicy -ManifestPath $inventory.ManifestPath -CaseNames $inventory.CaseNames
    $budget=1
    if($env:QUIETCLI_TEST_MAX_CONCURRENCY -and (![int]::TryParse($env:QUIETCLI_TEST_MAX_CONCURRENCY,[ref]$budget) -or $budget -lt 1 -or $budget -gt 32)){throw 'TestMaxConcurrencyInvalid'}
    $plan=Get-QuietTestExecutionPlan -CaseNames $selected.ToArray() -Policy $policy -MaxConcurrency $budget
    Write-WorkspaceJson (Join-Path $RunDirectory 'vagrant-execution-plan.json') $plan
    $batches=[Collections.Generic.List[object]]::new()
    foreach($stage in $plan.Stages){
        if($stoppedAt){$skipped+=$stage.Cases.Count;continue}
        if($stage.Mode -ceq 'IsolatedProcess' -and $env:QUIETCLI_TEST_CASE_WORKER -cne '1'){
            $counts=@{Passed=$passed;Failed=$failed}
            $batch=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Cases $stage.Cases.ToArray() -SuiteName 'Vagrant' -MaxConcurrency $plan.MaxConcurrency -StopOnFirstFailure:$stopOnFirst -SkipTty:($env:QUIETCLI_TEST_SKIP_TTY -ceq '1') -ExpectedRuntimeIdentifier $env:QUIETCLI_TEST_EXPECT_RID -OnCase {
                param($name,$caseState,$caseResult)
                if($caseState -ceq 'Passed'){$counts.Passed++}elseif($caseState -ceq 'Failed'){$counts.Failed++}
                if($OnProgress){& $OnProgress ('['+$caseMetadata[$name].TestKind+'] '+$name) $caseState $counts.Passed $counts.Failed}
            }
            $passed=$counts.Passed;$failed=$counts.Failed;$skipped+=$batch.NotStarted.Count;$batches.Add($batch)
            foreach($item in $batch.Cases){
                $item|Add-Member NoteProperty TestKind $caseMetadata[$item.Name].TestKind
                $item|Add-Member NoteProperty Dependencies @($caseMetadata[$item.Name].Dependencies)
                $results.Add($item)
            }
            if($stopOnFirst -and @($batch.Cases|Where-Object State -CEQ Failed).Count){$stoppedAt='Stopped after an observed failure'}
            continue
        }
        foreach($planned in $stage.Cases){
            if($stoppedAt){$skipped++;continue}
            $name=$planned.Name;$metadata=$caseMetadata[$name];$progressName='['+$metadata.TestKind+'] '+$name
            if($OnProgress){& $OnProgress $progressName 'Running' $passed $failed}
            $failure=$null
            try{$null=& $cases[$name];$passed++;$state='Passed'}catch{$failed++;$state='Failed';$failure=$_.Exception.Message}
            $results.Add([pscustomobject]@{Name=$name;State=$state;Error=$failure;TestKind=$metadata.TestKind;Dependencies=@($metadata.Dependencies);ExecutionMode=$planned.Mode})
            if($OnProgress){& $OnProgress $progressName $state $passed $failed}
            if($state -ceq 'Failed' -and $stopOnFirst){$stoppedAt='Stopped after an observed failure'}
        }
    }
    $transcriptsComplete=@($results|Where-Object {$_.Name -ceq 'bounded fuzz: random multi-machine --machine-readable transcripts survive arbitrary chunk fragmentation' -and $_.State -ceq 'Passed'}).Count -eq 1
    $malformedComplete=@($results|Where-Object {$_.Name -ceq 'bounded malformed timestamps and missing fields are rejected without partial events' -and $_.State -ceq 'Passed'}).Count -eq 1
    [pscustomobject]@{ Project='FrenchExDev2.QuietCli.Vagrant.PoSh';Passed=$passed;Failed=$failed;Partial=[bool]$pattern;Incomplete=[bool]$stoppedAt;StoppedAt=$stoppedAt;Skipped=$skipped;TtyExcluded=$ttyExcluded;Cases=$results.ToArray();FixtureDirectory=$root;Seed=20261108;FragmentedTranscripts=if($transcriptsComplete){200}else{$null};MalformedInputs=if($malformedComplete){800}else{$null};ExecutionPlan=$plan;ParallelBatches=$batches.ToArray()}
}
Export-ModuleMember -Function Invoke-QuietVagrantTests
