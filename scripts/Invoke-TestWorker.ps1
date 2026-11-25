#requires -Version 7.6
<#
.SYNOPSIS
Background worker for the companion suites; always persists a terminal report.
.PARAMETER WorkspaceRoot
QuietCli2 workspace root.
.PARAMETER RunDirectory
Private output directory for this run.
.PARAMETER Profiler
Enables a separate pinned PowerShell and CLR profiling pass, outside benchmark samples.
.PARAMETER ProfilerModulePath
Explicit Profiler 4.3.0 manifest; the launcher prepares a private cache when omitted.
.PARAMETER ClrProfilerPath
Explicit pinned dotnet-trace DLL.
.PARAMETER SkipTty
Excludes native TTY/PTY execution from this run; local runs include it by default.
.PARAMETER Suite
Core, Git, Vagrant, All, Import, mandatory Integration, explicit-repository RealStatus, or complete RunProfiles/RunProfilesMutation tooling qualification.
.PARAMETER RepositoryConfig
UTF-8 JSON array of existing repository roots; required by RealStatus.
.PARAMETER ExpectedRuntimeIdentifier
Required native architecture for both the PowerShell host and the separate engine.
.PARAMETER DotNetSuite
Focused .NET tooling campaign, used only with Suite DotNet.
.PARAMETER MaxConcurrency
Maximum number of internal test workers used by parallel-safe campaigns.
.PARAMETER CaseWorker
Internal single-case child: requires an ordinary declared companion and a case filter, forces one internal worker and prevents recursive case fan-out.
#>
[CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[string]$SmokeSuitesJson='[]',[string]$ExpectedRuntimeIdentifier,[string]$RepositoryConfig,[switch]$SkipTty,[switch]$Profiler,[string]$ProfilerModulePath,[string]$ClrProfilerPath,[string]$Case,[switch]$StopOnFirstFailure,[ValidateSet('Readiness','Provisioning','Layout','Locks','All')][string]$DotNetSuite='All',[ValidateRange(1,32)][int]$MaxConcurrency=[Math]::Min(4,[Math]::Max(1,[Environment]::ProcessorCount)),[switch]$CaseWorker)

dynamicparam {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceProjects.psm1')) -DisableNameChecking -ErrorAction Stop
    $selectedRoot=if($PSBoundParameters.ContainsKey('WorkspaceRoot')){$PSBoundParameters['WorkspaceRoot']}else{Split-Path $PSScriptRoot -Parent}
    New-QuietWorkspaceSuiteParameter -WorkspaceRoot $selectedRoot -Scope Host
}
end {
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/WorkspaceLayout.psm1')) -DisableNameChecking -ErrorAction Stop
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Invoke-TestWorker')){return}
$Suite=if($PSBoundParameters.ContainsKey('Suite')){[string]$PSBoundParameters['Suite']}else{'All'}
$ErrorActionPreference='Stop'
if($CaseWorker -and ($Suite -cnotin @(Get-QuietWorkspaceTestSuites $WorkspaceRoot).Name -or !$Case -or $MaxConcurrency -ne 1 -or $Profiler)){throw 'TestCaseWorkerArgumentsInvalid'}
$env:QUIETCLI_TEST_CASE_WORKER=if($CaseWorker){'1'}else{'0'}
$env:QUIETCLI_TEST_EXPECT_RID=$ExpectedRuntimeIdentifier
if($CaseWorker){$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE='0'}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
$previousTestPath=$env:PATH;$previousTestDotNetRoot=$env:DOTNET_ROOT
$testDotNet=Get-QuietWorkspaceDotNetHost $WorkspaceRoot
if($testDotNet){$env:PATH=$testDotNet.Directory+[IO.Path]::PathSeparator+$env:PATH;$env:DOTNET_ROOT=$testDotNet.Directory}
# Development selection is resolved by each owning companion; case workers receive an exact parent-selected filter.
$env:QUIETCLI_TEST_SKIP_TTY=if($SkipTty){'1'}else{'0'}
$env:QUIETCLI_TEST_MAX_CONCURRENCY=[string]$MaxConcurrency
if($Case){$env:QUIETCLI_TEST_CASE=$Case}
if($StopOnFirstFailure){$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE='1'}
$moduleContainers=@(Get-QuietWorkspaceProjects $WorkspaceRoot|ForEach-Object {[IO.Path]::GetDirectoryName($_.Directory)}|Select-Object -Unique)
$env:PSModulePath=($moduleContainers -join [IO.Path]::PathSeparator)+[IO.Path]::PathSeparator+$env:PSModulePath
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/TestConfiguration.psm1')) -DisableNameChecking -ErrorAction Stop
$testHosting=if($env:QUIETCLI_EXPECT_ENGINE_MODE){$env:QUIETCLI_EXPECT_ENGINE_MODE}else{'Auto'}
Initialize-QuietTestConfiguration -DatabasePath ([IO.Path]::Combine($RunDirectory,'measurements.sqlite')) -Hosting $testHosting
$env:QUIETCLI_RECALL_TEST_ROOT=[IO.Path]::Combine($RunDirectory,'recall-csharp')
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='Tests compagnons';Workspace=$WorkspaceRoot;ProjectDirectory=((Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath 'FrenchExDev2.QuietCli.Core.PoSh'));Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');ProcessId=$PID;Passed=0;Failed=0;TtyExcluded=[bool]$SkipTty;Case='Starting';FinishedUtc=$null;Error=$null}
$statusPath=[IO.Path]::Combine($RunDirectory,'status.json')
if($Suite -in @('CompanionSmoke','WorkspaceLayout','DotNet','RunProfiles','GalleryPreview','Script','AgentInstructions','ConfigurationDelivery','Recall','RecallLarge','Integration','RealStatus','Import')){
    $state.TestPassed=0;$state.TestFailed=0
}
$pesterProgress={
    param($name,$caseState,$passed,$failed)
    $state.Case="[$caseState] $name"
    $state.Passed=$state.TestPassed=$passed
    $state.Failed=$state.TestFailed=$failed
    Write-WorkspaceJson $statusPath $state
}
Write-WorkspaceJson $statusPath $state
$summaries=[Collections.Generic.List[object]]::new()
$sourceIdentity=$null;$engineIdentity=$null;$profiling=$null
try{
    if($env:QUIETCLI_PROFILE_COMPANION){
        Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/RunProfiler.psm1')) -DisableNameChecking -ErrorAction Stop
    }
    if($env:QUIETCLI_EXPECT_RUNTIME_MAJOR -and [Environment]::Version.Major -ne [int]$env:QUIETCLI_EXPECT_RUNTIME_MAJOR){throw 'PowerShellRuntimeMajorMismatch'}
    if($env:QUIETCLI_EXPECT_HOST_VERSION -and $PSVersionTable.PSVersion.ToString() -cne $env:QUIETCLI_EXPECT_HOST_VERSION){throw 'PowerShellVersionMismatch'}
    if($ExpectedRuntimeIdentifier -and $state.Platform -cne $ExpectedRuntimeIdentifier){throw "HostRuntimeMismatch: expected $ExpectedRuntimeIdentifier, observed $($state.Platform)"}
    $sourceIdentity=Get-QuietWorkspaceIdentity $WorkspaceRoot -Suite $Suite -IncludeBinaries:($Suite -notin @('AgentInstructions','DotNet','RunProfilesMutation','WorkspaceLayout','CompanionSmoke'))
    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'source-identity.json')) $sourceIdentity
    if($Suite -notin @('DotNet','RunProfilesMutation','WorkspaceLayout','CompanionSmoke')){
    Import-Module ([IO.Path]::Combine($WorkspaceRoot,'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')) -Force -DisableNameChecking
    $expectedCorePath=[IO.Path]::GetFullPath(([IO.Path]::Combine($WorkspaceRoot,'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psm1')))
    $actualCorePath=(Get-Command FrenchExDev2.QuietCli.Core.PoSh\Invoke-QuietCli -ErrorAction Stop).Module.Path
    if(![StringComparer]::OrdinalIgnoreCase.Equals($actualCorePath,$expectedCorePath)){throw 'UnexpectedCoreModulePath'}
    $localAlias=Get-Alias quiet -ErrorAction Stop
    if(!$localAlias.ResolvedCommand -or ![StringComparer]::OrdinalIgnoreCase.Equals($localAlias.ResolvedCommand.Module.Path,$expectedCorePath)){throw 'UnexpectedQuietAliasTarget'}
    }
    if($Suite -eq 'CompanionSmoke'){
        Import-Module ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/CompanionSmoke.Tests.psm1')) -DisableNameChecking -ErrorAction Stop
        $state.Project='Selected companions';$state.Task='Companion integration smoke'
        $summary=Invoke-QuietCompanionSmokeTests -WorkspaceRoot $WorkspaceRoot -Suites @(ConvertFrom-Json $SmokeSuitesJson) -RunDirectory $RunDirectory -OnProgress $pesterProgress
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -eq 'WorkspaceLayout'){
        Import-Module ([IO.Path]::Combine($WorkspaceRoot,'src/Tooling/test/FrenchExDev2.QuietCli.Tooling.Tests.PoSh/WorkspaceLayout.Tests.psm1')) -DisableNameChecking -ErrorAction Stop
        $state.Project='FrenchExDev2.QuietCli.Tooling.Tests.PoSh';$state.ProjectDirectory=Resolve-QuietWorkspacePath $WorkspaceRoot $state.Project;$state.Task='Grouped workspace and selective CI'
        $summary=Invoke-QuietWorkspaceLayoutTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress $pesterProgress
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -eq 'DotNet'){
        . ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-DotNetQualification.ps1'))
        $state.Project='FrenchExDev2.QuietCli.Core.Tests.PoSh';$state.ProjectDirectory=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $state.Project);$state.Task='Offline .NET toolchain automation'
        $summary=Invoke-QuietDotNetQualification -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Suite $DotNetSuite -OnProgress $pesterProgress
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -in @('Tooling','Distribution')){
        # RequiredModules do not inherit the importing companion's DisableNameChecking option.
        Import-Module (Resolve-QuietWorkspacePath $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -DisableNameChecking -ErrorAction Stop
        $testModule='FrenchExDev2.QuietCli.'+$Suite+'.Tests.PoSh'
        $testManifest=Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath ($testModule+'/'+$testModule+'.psd1')
        Import-Module $testManifest -DisableNameChecking -ErrorAction Stop
        $runnerName=(Import-PowerShellDataFile -LiteralPath $testManifest).PrivateData.QuietCli.TestCatalogue.Runner
        $state.Project=$testModule;$state.Task=$Suite+' qualification'
        $state.TestPassed=0;$state.TestFailed=0
        $toolingState=$state
        $summary=& (Get-Command ($testModule+'\'+$runnerName) -ErrorAction Stop) -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress {
            param($name,$caseState,$passed,$failed)
            $toolingState.Case="[$caseState] $name";$toolingState.Passed=$toolingState.TestPassed=$passed;$toolingState.Failed=$toolingState.TestFailed=$failed;Write-WorkspaceJson $statusPath $toolingState
            if($env:GITHUB_ACTIONS -ceq 'true'){Write-Host ("CI case [$caseState] $name | passed=$passed failed=$failed")}
        }
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -in @('RunProfiles','RunProfilesMutation')){
        . ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-RunProfileQualification.ps1'))
        $state.Project='FrenchExDev2.QuietCli.Core.Tests.PoSh';$state.ProjectDirectory=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $state.Project);$state.Task=$Suite
        $runProfileState=$state
        $parameters=@{
            WorkspaceRoot=$WorkspaceRoot;RunDirectory=$RunDirectory;Mutation=($Suite -eq 'RunProfilesMutation')
            MaxConcurrency=[Math]::Min(2,$MaxConcurrency)
            OnProgress={
                param($name,$passed,$failed)
                $runProfileState.Case=$name;$runProfileState.Passed=$passed;$runProfileState.Failed=$failed
                if($runProfileState.ContainsKey('TestPassed')){$runProfileState.TestPassed=$passed;$runProfileState.TestFailed=$failed}
                Write-WorkspaceJson $statusPath $runProfileState
            }
        }
        if($env:QUIETCLI_PROFILE_COMPANION -ceq $Suite){
            $command=Get-Command Invoke-RunProfileQualification -CommandType Function -ErrorAction Stop
            $profiled=Invoke-QuietProfiledTestCommand -TestCommand ({& $command @parameters}.GetNewClosure()) -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Suite $Suite
            $summary=$profiled.Output[0]
            $profiling=$profiled.Profiling
        }else{$summary=Invoke-RunProfileQualification @parameters}
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -eq 'GalleryPreview'){
        . ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/GalleryPreview.Tests.ps1'))
        $state.Project='FrenchExDev2.QuietCli.Core.Tests.PoSh';$state.ProjectDirectory=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $state.Project);$state.Task='Preview packages, properties, fuzz corpus and mutations'
        $summary=Invoke-QuietGalleryPreviewTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Mutation -OnProgress $pesterProgress
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -eq 'Script'){
        . ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Script.Tests.ps1'))
        $state.Task='Reusable scripts, factories, property corpus and mutations'
        $summary=Invoke-QuietScriptTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress $pesterProgress
        $summaries.Add($summary)
    }elseif($Suite -eq 'AgentInstructions'){
        . ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/AgentInstructions.Tests.ps1'))
        $state.Task='Production agent instructions and installed resource qualification'
        $summary=Invoke-QuietAgentInstructionTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress $pesterProgress
        $summaries.Add($summary)
    }elseif($Suite -eq 'ConfigurationDelivery'){
        . ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/ConfigurationDelivery.Tests.ps1'))
        $state.Task='Configuration, tokenization and unique delivery qualification'
        $summary=Invoke-QuietConfigurationDeliveryTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Mutation -OnPesterProgress $pesterProgress -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -in @('Recall','RecallMutation','RecallLarge')){
        Import-Module ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1')) -DisableNameChecking
        $state.Task=$Suite+' capture and analyzer qualification'
        if($Suite -eq 'Recall'){
            $summary=Invoke-QuietRecallTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress $pesterProgress
        }elseif($Suite -eq 'RecallLarge'){
            $summary=Invoke-QuietRecallLargeTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress $pesterProgress
        }else{
            . ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Recall.Mutation.ps1'))
            $summary=Invoke-QuietRecallMutation -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
        }
        $summaries.Add($summary)
    }elseif($Suite -eq 'Integration'){
        $state.Task='Core integration: import and controlled Git states'
        . ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Integration.Tests.ps1'))
        $summary=Invoke-QuietCoreIntegrationTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress $pesterProgress
        $summaries.Add($summary)
    }elseif($Suite -eq 'RealStatus'){
        $state.Task='Real repository git status with Core callbacks only'
        . ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Status.Real.Tests.ps1'))
        $summary=Invoke-QuietRealStatusIntegration -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -RepositoryConfig $RepositoryConfig -OnProgress $pesterProgress
        $summaries.Add($summary)
    }elseif($Suite -eq 'Import'){
        $state.Task='Core import cost in fresh pwsh sessions'
        . ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/Import.Tests.ps1'))
        Import-Module ([IO.Path]::Combine($WorkspaceRoot,'scripts/lib/PesterProgress.psm1')) -DisableNameChecking -ErrorAction Stop
        $importEvidence=@{}
        $importCases=[ordered]@{'Fresh pwsh import identity, inertness and cost'={
            $importEvidence.Value=Invoke-QuietImportIntegration -WorkspaceRoot $WorkspaceRoot -OnProgress {
                param($name,$caseState)
                if($caseState -ceq 'Running'){$null=& $pesterProgress $name 'Running' 0 0}
            }
        }}
        $summary=Invoke-QuietPesterCaseTable -WorkspaceRoot $WorkspaceRoot -Suite Import -Cases $importCases -OnProgress $pesterProgress -InvokePester {param($configuration) Pester\Invoke-Pester -Configuration $configuration}
        if($importEvidence.Value){$summary=$importEvidence.Value}
        $summaries.Add($summary)
    }else{
        $engineIdentity=Get-QuietEngine
        if($env:QUIETCLI_EXPECT_ENGINE_MODE -and $engineIdentity.Mode -cne $env:QUIETCLI_EXPECT_ENGINE_MODE){throw 'EngineHostingModeMismatch'}
        if($env:QUIETCLI_EXPECT_RUNTIME_MAJOR -and $engineIdentity.Mode -eq 'InProcess'){
            $framework='.NETCoreApp,Version=v'+$env:QUIETCLI_EXPECT_RUNTIME_MAJOR+'.0'
            if($engineIdentity.Mode -cne 'InProcess' -or $engineIdentity.Engine.ProcessId -ne $PID -or $engineIdentity.Engine.TargetFramework -cne $framework){throw 'IntegratedEngineIdentityMismatch'}
            if($engineIdentity.ProtocolInputBytes -ne 0 -or $engineIdentity.ProtocolOutputBytes -ne 0){throw 'IntegratedEngineUnexpectedPipeTraffic'}
        }
        if($ExpectedRuntimeIdentifier -and $engineIdentity.Engine.RuntimeIdentifier -cne $ExpectedRuntimeIdentifier){throw "EngineRuntimeMismatch: expected $ExpectedRuntimeIdentifier, observed $($engineIdentity.Engine.RuntimeIdentifier)"}
        if($ExpectedRuntimeIdentifier -and $engineIdentity.Mode -ne 'InProcess' -and $engineIdentity.Engine.BuildRuntimeIdentifier -cne $ExpectedRuntimeIdentifier){throw 'EnginePublicationRuntimeMismatch'}
        # RequiredModules imports do not inherit DisableNameChecking from the importing companion.
        Import-Module ([IO.Path]::Combine($WorkspaceRoot,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1')) -DisableNameChecking -ErrorAction Stop
        # Parser/handler qualification uses the owned process fixture; it never installs Vagrant or a provider.
        $selections=@(Get-QuietWorkspaceSuiteSelection -WorkspaceRoot $WorkspaceRoot -Suite $Suite)
        $parallelCompanions=$Suite -eq 'All' -and @($selections|Where-Object Name -CEQ Core).Count -eq 1
        if($parallelCompanions){$selections=@($selections|Sort-Object {if($_.Name -ceq 'Core'){0}else{1}})}
        $state.TestPassed=0;$state.TestFailed=0
        foreach($selection in $selections){
            if($parallelCompanions -and $selection.Name -cne 'Core'){continue}
            $selected=$selection.Name
            $project=$selection.Project
            $state.Project=$project;$state.ProjectDirectory=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $project)
            Import-Module $selection.TestsManifest -Force -DisableNameChecking
            $basePassed=$state.Passed;$baseFailed=$state.Failed
            $progress={
                param($name,$caseState,$passed,$failed)
                $state.Case="[$caseState] $name"
                $state.Passed=$state.TestPassed=$basePassed+$passed
                $state.Failed=$state.TestFailed=$baseFailed+$failed
                Write-WorkspaceJson $statusPath $state
                if($env:GITHUB_ACTIONS -ceq 'true' -and !$CaseWorker){Write-Host ("CI case [$caseState] $name | passed=$($state.Passed) failed=$($state.Failed)")}
            }
            $command=Get-Command ($selection.TestsModule+'\'+$selection.Command) -ErrorAction Stop
            $parameters=@{WorkspaceRoot=$WorkspaceRoot;OnProgress=$progress}
            if($command.Parameters.ContainsKey('RunDirectory')){$parameters.RunDirectory=$RunDirectory}
            if($env:QUIETCLI_PROFILE_COMPANION -ceq $selected){
                $profiled=Invoke-QuietProfiledTestCommand -TestCommand ({& $command @parameters}.GetNewClosure()) -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Suite $selected
                $outputs=$profiled.Output
                $profiling=$profiled.Profiling
            }else{$outputs=@(& $command @parameters)}
            if($outputs.Count -ne 1){throw ('CompanionRunnerMustReturnOneSummary: '+$selection.Name)}
            $summary=$outputs[0]
            $summaries.Add($summary)
            Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,($selected.ToLowerInvariant()+'-suite.json'))) $summary
            if($summary.PSObject.Properties['Partial'] -and ($summary.Partial -or $summary.Incomplete)){
                # Filtered or stopped development run: not qualification evidence, so the full-run evidence assertion is skipped.
                $state.Task+=if($summary.Incomplete){" [INCOMPLETE: $($summary.StoppedAt)]"}else{' [PARTIAL: case filter]'}
                Write-WorkspaceJson $statusPath $state
            }elseif($selected -eq 'Core' -and !$summary.Failed){& ([IO.Path]::Combine($PSScriptRoot,'Assert-CoreIntegrationEvidence.ps1')) -Summary $summary}
            if($parallelCompanions -and ($summary.Failed -or $summary.Partial -or $summary.Incomplete)){throw 'CompanionFanoutRequiresSuccessfulCompleteCore'}
        }
        if($parallelCompanions){
            Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiCompanionWorkers.psm1')) -DisableNameChecking
            $corePassed=$state.Passed;$coreFailed=$state.Failed
            $children=@(Invoke-QuietCiCompanionWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -CoreSummary $summary -Selections @($selections|Where-Object Name -CNE Core) -SkipTty:$SkipTty -ExpectedRuntimeIdentifier $ExpectedRuntimeIdentifier -MaxConcurrency ([Math]::Min(2,$MaxConcurrency)) -WorkerBudget $MaxConcurrency -OnProgress {
                param($passed,$failed)
                $state.Case='Core accepted; independent companion suites running'
                $state.Passed=$state.TestPassed=$corePassed+$passed
                $state.Failed=$state.TestFailed=$coreFailed+$failed
                Write-WorkspaceJson $statusPath $state
            })
            foreach($child in $children){foreach($summary in $child.Suites){$summaries.Add($summary)}}
        }
    }
    if(@($summaries|Where-Object {$_.PSObject.Properties['Partial'] -and $_.Partial}).Count -and $state.Task -notlike '*PARTIAL*'){$state.Task+=' [PARTIAL: case filter]'}
    if($Profiler){
        if($Suite -notin @('Core','All','Integration')){throw 'ProfilerRequiresCoreIntegration'}
        $state.Project='FrenchExDev2.QuietCli.Core.PoSh';$state.ProjectDirectory=(Resolve-QuietWorkspacePath -WorkspaceRoot $WorkspaceRoot -RelativePath $state.Project);$state.Task='Core PowerShell and CLR profiling';$state.Case='Attaching profilers to owned targets';Write-WorkspaceJson $statusPath $state
        $profiling=& ([IO.Path]::Combine($PSScriptRoot,'Invoke-CoreProfiling.ps1')) -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -ProfilerModulePath $ProfilerModulePath -ClrProfilerPath $ClrProfilerPath
    }
    $state.State=if($state.Failed){'Failed'}else{'Success'}
}catch{$state.State='Crash';$state.Error=$_.ToString();$state.Failed++;Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'worker-failure.json')) @{Message=$_.Exception.Message;Stack=$_.ScriptStackTrace;Position=$_.InvocationInfo.PositionMessage}}
finally{
    if($sourceIdentity){
        try{
            $after=Get-QuietWorkspaceIdentity $WorkspaceRoot -Suite $Suite -IncludeBinaries:($Suite -notin @('AgentInstructions','DotNet','RunProfilesMutation','WorkspaceLayout','CompanionSmoke'))
            $drift=@(foreach($before in $sourceIdentity.Projects){$current=@($after.Projects|Where-Object Name -CEQ $before.Name)[0];if($current.SourceSHA256 -cne $before.SourceSHA256){$before.Name}};if($sourceIdentity.Repository.SourceSHA256 -cne $after.Repository.SourceSHA256){'Monorepo'})
            if($drift.Count){$state.State='Failed';$state.Failed++;$state.Case='Sources changed during the run';$state.Error=$drift -join ', '}
            Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'source-identity-final.json')) $after
            if($Suite -notin @('Import','DotNet','RunProfilesMutation','WorkspaceLayout')){$engineIdentity=Get-QuietEngine}
            if($Suite -notin @('Import','DotNet','RunProfilesMutation','WorkspaceLayout') -and $ExpectedRuntimeIdentifier -and $engineIdentity.Engine.RuntimeIdentifier -cne $ExpectedRuntimeIdentifier){throw 'FinalEngineRuntimeMismatch'}
        }catch{$state.State='Failed';$state.Failed++;$state.Error='Build/source identity verification failed: '+$_.Exception.Message}
    }
    if($Suite -notin @('DotNet','RunProfilesMutation','WorkspaceLayout')){try{Stop-QuietEngine}catch{}}
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson ([IO.Path]::Combine($RunDirectory,'summary.json')) @{State=$state;Suites=$summaries.ToArray();Profiling=$profiling;EngineIdentity=$engineIdentity;HostRuntime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;PowerShellVersion=$PSVersionTable.PSVersion.ToString();OSArchitecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();ProcessArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();OSDescription=[Runtime.InteropServices.RuntimeInformation]::OSDescription;MachineName=[Environment]::MachineName;ExpectedRuntimeIdentifier=$ExpectedRuntimeIdentifier;RunnerImage=$env:ImageOS;RunnerImageVersion=$env:ImageVersion}
    Write-WorkspaceJson $statusPath $state
    $env:PATH=$previousTestPath;$env:DOTNET_ROOT=$previousTestDotNetRoot
}
if($state.State -ne 'Success'){exit 1}

}
