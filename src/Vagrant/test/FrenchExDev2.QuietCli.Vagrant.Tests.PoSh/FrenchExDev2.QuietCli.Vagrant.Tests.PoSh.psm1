foreach($library in @('TestCaseMetadata','TestCaseScheduling')){
    $path=Join-Path ([IO.Path]::GetFullPath('../../../..',$PSScriptRoot)) ('scripts/lib/'+$library+'.psm1')
    if(Test-Path -LiteralPath $path){Import-Module $path -ErrorAction Stop}
}
. (Join-Path $PSScriptRoot 'VagrantLine.Tests.ps1')
. (Join-Path $PSScriptRoot 'VagrantFuzz.Tests.ps1')
. (Join-Path $PSScriptRoot 'VagrantParser.Mutation.ps1')
. (Join-Path $PSScriptRoot '../../src/FrenchExDev2.QuietCli.Vagrant.PoSh/src/Commands.ps1')
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
    Import-Module (Join-Path $WorkspaceRoot 'scripts/lib/Common.psm1') -DisableNameChecking -ErrorAction Stop
    if (!$RunDirectory) { $RunDirectory = Join-Path (Get-QuietReportRoot $WorkspaceRoot 'tests') ([guid]::NewGuid().ToString('N')) }
    $root = Join-Path $RunDirectory 'vagrant-fixtures'
    [void][IO.Directory]::CreateDirectory($root)
    $RootDirectory = $root
    $dotnet = (Get-Command dotnet -CommandType Application | Select-Object -First 1).Source
    $fixture = Join-Path $WorkspaceRoot 'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/lib/fixture/QuietCli.Fixture.dll'
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
            if($env:QUIETCLI_CAMPAIGN_REPORT_ROOT){
                [void][IO.Directory]::CreateDirectory($env:QUIETCLI_CAMPAIGN_REPORT_ROOT)
                [IO.File]::Copy([IO.Path]::Combine($mutationRoot,'summary.json'),[IO.Path]::Combine($env:QUIETCLI_CAMPAIGN_REPORT_ROOT,'vagrant-parser.json'))
            }
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
        'the Vagrant factory prepares callbacks that emit valid events and set the Ui header and lanes'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState','ProcessEnvironment')}
        'up and provision factories produce the same events and lanes from the same transcript'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        '--no-provision is purely the absence of the trigger line: zero ProvisionerStarted events, no special-casing'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'a silent machine keeps its last-written lane entry while another machine keeps advancing'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'registered Vagrant handlers deliver live events through the outer native pipeline and preserve failure visibility'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'bounded fuzz: random multi-machine --machine-readable transcripts survive arbitrary chunk fragmentation'=@{TestKind='Integration';Dependencies=@('FileSystem','NativeProcess','EngineState')}
        'bounded malformed timestamps and missing fields are rejected without partial events'=@{TestKind='Unit';Dependencies=@()}
    }
    $inventory=Get-QuietCompanionTestInventory -ManifestPath (Join-Path $PSScriptRoot 'FrenchExDev2.QuietCli.Vagrant.Tests.PoSh.psd1')
    Assert-QuietTestCaseMetadata -CaseNames $inventory.CaseNames -Metadata $caseMetadata
    $ttyExcluded=0;$skipped=0
    $selected=[Collections.Generic.List[string]]::new()
    $activeMetadata=Get-QuietActiveCaseMetadata -Metadata $caseMetadata
    Assert-QuietTestCaseMetadata -CaseNames @($cases.Keys) -Metadata $activeMetadata
    $pattern=$env:QUIETCLI_TEST_CASE
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
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/PesterProgress.psm1')) -DisableNameChecking -ErrorAction Stop
    $pesterResult=Invoke-QuietPesterCompanionPlan -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Suite 'Vagrant' `
        -Plan $plan -Cases $cases -Metadata $caseMetadata -OnProgress $OnProgress `
        -InvokePester {param($configuration) Pester\Invoke-Pester -Configuration $configuration}
    $transcriptsComplete=@($pesterResult.Cases|Where-Object {$_.Name -ceq 'bounded fuzz: random multi-machine --machine-readable transcripts survive arbitrary chunk fragmentation' -and $_.State -ceq 'Passed'}).Count -eq 1
    $malformedComplete=@($pesterResult.Cases|Where-Object {$_.Name -ceq 'bounded malformed timestamps and missing fields are rejected without partial events' -and $_.State -ceq 'Passed'}).Count -eq 1
    [pscustomobject]@{ Project='FrenchExDev2.QuietCli.Vagrant.PoSh';Passed=$pesterResult.Passed;Failed=$pesterResult.Failed;Partial=[bool]$pattern;Incomplete=[bool]$pesterResult.StoppedAt;StoppedAt=$pesterResult.StoppedAt;Skipped=($skipped+$pesterResult.Skipped);TtyExcluded=$ttyExcluded;Cases=$pesterResult.Cases;FixtureDirectory=$root;Seed=20261108;FragmentedTranscripts=if($transcriptsComplete){200}else{$null};MalformedInputs=if($malformedComplete){800}else{$null};ExecutionPlan=$plan;ParallelBatches=$pesterResult.ParallelBatches}
}
Export-ModuleMember -Function Invoke-QuietVagrantTests
