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
Internal single-case child: requires Core and a case filter, forces one internal worker and prevents recursive case fan-out.
#>
[CmdletBinding(SupportsShouldProcess)]param([Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,[string]$ExpectedRuntimeIdentifier,[string]$RepositoryConfig,[switch]$SkipTty,[switch]$Profiler,[string]$ProfilerModulePath,[string]$ClrProfilerPath,[string]$Case,[switch]$StopOnFirstFailure,[ValidateSet('Readiness','Provisioning','Layout','Locks','All')][string]$DotNetSuite='All',[ValidateRange(1,32)][int]$MaxConcurrency=[Math]::Min(4,[Math]::Max(1,[Environment]::ProcessorCount)),[switch]$CaseWorker)
dynamicparam {
    . (Join-Path $PSScriptRoot 'WorkspaceProjects.ps1')
    $selectedRoot=if($PSBoundParameters.ContainsKey('WorkspaceRoot')){$PSBoundParameters['WorkspaceRoot']}else{Split-Path $PSScriptRoot -Parent}
    New-QuietWorkspaceSuiteParameter -WorkspaceRoot $selectedRoot -Scope Host
}
end {
if(!$PSCmdlet.ShouldProcess($PSCommandPath,'Execute automation: Invoke-TestWorker')){return}
$Suite=if($PSBoundParameters.ContainsKey('Suite')){[string]$PSBoundParameters['Suite']}else{'All'}
$ErrorActionPreference='Stop'
if($CaseWorker -and ($Suite -cne 'Core' -or !$Case -or $MaxConcurrency -ne 1 -or $Profiler)){throw 'TestCaseWorkerArgumentsInvalid'}
$env:QUIETCLI_TEST_CASE_WORKER=if($CaseWorker){'1'}else{'0'}
$env:QUIETCLI_TEST_EXPECT_RID=$ExpectedRuntimeIdentifier
if($CaseWorker){$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE='0'}
. (Join-Path $PSScriptRoot 'Common.ps1')
# Development-only selection, read by the Core case loop; never set by CI or the pre-commit gate.
$env:QUIETCLI_TEST_SKIP_TTY=if($SkipTty){'1'}else{'0'}
$env:QUIETCLI_TEST_MAX_CONCURRENCY=[string]$MaxConcurrency
if($Case){$env:QUIETCLI_TEST_CASE=$Case}
if($StopOnFirstFailure){$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE='1'}
$env:PSModulePath=$WorkspaceRoot+[IO.Path]::PathSeparator+$env:PSModulePath
. (Join-Path $PSScriptRoot 'TestConfiguration.ps1')
$testHosting=if($env:QUIETCLI_EXPECT_ENGINE_MODE){$env:QUIETCLI_EXPECT_ENGINE_MODE}else{'Auto'}
Initialize-QuietTestConfiguration -DatabasePath (Join-Path $RunDirectory 'measurements.sqlite') -Hosting $testHosting
$env:QUIETCLI_RECALL_TEST_ROOT=Join-Path $RunDirectory 'recall-csharp'
$state=@{Project='FrenchExDev2.QuietCli.Core.PoSh';Task='Tests compagnons';Workspace=$WorkspaceRoot;ProjectDirectory=(Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh');Platform=[Runtime.InteropServices.RuntimeInformation]::RuntimeIdentifier;State='Running';StartedUtc=[DateTimeOffset]::UtcNow.ToString('o');ProcessId=$PID;Passed=0;Failed=0;TtyExcluded=[bool]$SkipTty;Case='Starting';FinishedUtc=$null;Error=$null}
$statusPath=Join-Path $RunDirectory 'status.json'
Write-WorkspaceJson $statusPath $state
$summaries=[Collections.Generic.List[object]]::new()
$sourceIdentity=$null;$engineIdentity=$null;$profiling=$null
try{
    if($env:QUIETCLI_EXPECT_RUNTIME_MAJOR -and [Environment]::Version.Major -ne [int]$env:QUIETCLI_EXPECT_RUNTIME_MAJOR){throw 'PowerShellRuntimeMajorMismatch'}
    if($env:QUIETCLI_EXPECT_HOST_VERSION -and $PSVersionTable.PSVersion.ToString() -cne $env:QUIETCLI_EXPECT_HOST_VERSION){throw 'PowerShellVersionMismatch'}
    if($ExpectedRuntimeIdentifier -and $state.Platform -cne $ExpectedRuntimeIdentifier){throw "HostRuntimeMismatch: expected $ExpectedRuntimeIdentifier, observed $($state.Platform)"}
    $sourceIdentity=Get-QuietWorkspaceIdentity $WorkspaceRoot -IncludeBinaries:($Suite -notin @('AgentInstructions','DotNet'))
    Write-WorkspaceJson (Join-Path $RunDirectory 'source-identity.json') $sourceIdentity
    if($Suite -ne 'DotNet'){
    Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1') -Force
    $expectedCorePath=[IO.Path]::GetFullPath((Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psm1'))
    $actualCorePath=(Get-Command FrenchExDev2.QuietCli.Core.PoSh\Invoke-QuietCli -ErrorAction Stop).Module.Path
    if(![StringComparer]::OrdinalIgnoreCase.Equals($actualCorePath,$expectedCorePath)){throw 'UnexpectedCoreModulePath'}
    $localAlias=Get-Alias quiet -ErrorAction Stop
    if(!$localAlias.ResolvedCommand -or ![StringComparer]::OrdinalIgnoreCase.Equals($localAlias.ResolvedCommand.Module.Path,$expectedCorePath)){throw 'UnexpectedQuietAliasTarget'}
    }
    if($Suite -eq 'DotNet'){
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-DotNetQualification.ps1')
        $state.Project='FrenchExDev2.QuietCli.Core.Tests.PoSh';$state.ProjectDirectory=Join-Path $WorkspaceRoot $state.Project;$state.Task='Offline .NET toolchain automation'
        $dotnetWorkerState=$state
        $summary=Invoke-QuietDotNetQualification -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Suite $DotNetSuite -OnProgress {param($name,$passed,$failed)$dotnetWorkerState.Case=$name;$dotnetWorkerState.Passed=$passed;$dotnetWorkerState.Failed=$failed;Write-WorkspaceJson $statusPath $dotnetWorkerState}
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -in @('RunProfiles','RunProfilesMutation')){
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/Invoke-RunProfileQualification.ps1')
        $state.Project='FrenchExDev2.QuietCli.Core.Tests.PoSh';$state.ProjectDirectory=Join-Path $WorkspaceRoot $state.Project;$state.Task=$Suite
        $runProfileState=$state
        $summary=Invoke-RunProfileQualification -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Mutation:($Suite -eq 'RunProfilesMutation') -OnProgress {param($name,$passed,$failed)$runProfileState.Case=$name;$runProfileState.Passed=$passed;$runProfileState.Failed=$failed;Write-WorkspaceJson $statusPath $runProfileState}
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -eq 'GalleryPreview'){
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/GalleryPreview.Tests.ps1')
        $galleryWorkerState=$state
        $state.Project='FrenchExDev2.QuietCli.Core.Tests.PoSh';$state.ProjectDirectory=Join-Path $WorkspaceRoot $state.Project;$state.Task='Preview packages, properties, fuzz corpus and mutations'
        $summary=Invoke-QuietGalleryPreviewTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Mutation -OnProgress {param($name,$caseState,$passed,$failed)$galleryWorkerState.Case=$name;$galleryWorkerState.Passed=$passed;$galleryWorkerState.Failed=$failed;Write-WorkspaceJson $statusPath $galleryWorkerState}
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -eq 'Script'){
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/Script.Tests.ps1')
        $state.Task='Reusable scripts, factories, property corpus and mutations'
        $summary=Invoke-QuietScriptTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
        $summaries.Add($summary)
    }elseif($Suite -eq 'AgentInstructions'){
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/AgentInstructions.Tests.ps1')
        $state.Task='Production agent instructions and installed resource qualification'
        $summary=Invoke-QuietAgentInstructionTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
        $summaries.Add($summary)
    }elseif($Suite -eq 'ConfigurationDelivery'){
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/ConfigurationDelivery.Tests.ps1')
        $state.Task='Configuration, tokenization and unique delivery qualification'
        $summary=Invoke-QuietConfigurationDeliveryTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Mutation -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
        $state.Passed=$summary.Passed;$state.Failed=$summary.Failed;$summaries.Add($summary)
    }elseif($Suite -in @('Recall','RecallMutation','RecallLarge')){
        Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -DisableNameChecking
        $state.Task=$Suite+' capture and analyzer qualification'
        if($Suite -eq 'Recall'){
            $summary=Invoke-QuietRecallTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
        }elseif($Suite -eq 'RecallLarge'){
            $summary=Invoke-QuietRecallLargeTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
        }else{
            . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/Recall.Mutation.ps1')
            $summary=Invoke-QuietRecallMutation -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
        }
        $summaries.Add($summary)
    }elseif($Suite -eq 'Integration'){
        $state.Task='Core integration: import and controlled Git states'
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/Integration.Tests.ps1')
        $summary=Invoke-QuietCoreIntegrationTests -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
        $summaries.Add($summary)
    }elseif($Suite -eq 'RealStatus'){
        $state.Task='Real repository git status with Core callbacks only'
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/Status.Real.Tests.ps1')
        $summary=Invoke-QuietRealStatusIntegration -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -RepositoryConfig $RepositoryConfig -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
        $summaries.Add($summary)
    }elseif($Suite -eq 'Import'){
        $state.Task='Core import cost in fresh pwsh sessions'
        . (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/Import.Tests.ps1')
        $summary=Invoke-QuietImportIntegration -WorkspaceRoot $WorkspaceRoot -OnProgress {param($name,$caseState,$passed,$failed)$state.Case=$name;$state.Passed=$passed;$state.Failed=$failed;Write-WorkspaceJson $statusPath $state}
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
        Import-Module (Join-Path $WorkspaceRoot 'FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1') -DisableNameChecking -ErrorAction Stop
        # Parser/handler qualification uses the owned process fixture; it never installs Vagrant or a provider.
        $selections=@(Get-QuietWorkspaceSuiteSelection -WorkspaceRoot $WorkspaceRoot -Suite $Suite)
        $parallelCompanions=$Suite -eq 'All' -and @($selections|Where-Object Name -CEQ Core).Count -eq 1
        if($parallelCompanions){$selections=@($selections|Sort-Object {if($_.Name -ceq 'Core'){0}else{1}})}
        foreach($selection in $selections){
            if($parallelCompanions -and $selection.Name -cne 'Core'){continue}
            $selected=$selection.Name
            $project=$selection.Project
            $state.Project=$project;$state.ProjectDirectory=Join-Path $WorkspaceRoot $project
            Import-Module $selection.TestsManifest -Force -DisableNameChecking
            $basePassed=$state.Passed;$baseFailed=$state.Failed
            $progress={
                param($name,$caseState,$passed,$failed)
                $state.Case=$name;$state.Passed=$basePassed+$passed;$state.Failed=$baseFailed+$failed
                Write-WorkspaceJson $statusPath $state
                if($env:GITHUB_ACTIONS -ceq 'true' -and !$CaseWorker){Write-Host ("CI case [$caseState] $name | passed=$($state.Passed) failed=$($state.Failed)")}
            }
            $command=Get-Command ($selection.TestsModule+'\'+$selection.Command) -ErrorAction Stop
            $parameters=@{WorkspaceRoot=$WorkspaceRoot;OnProgress=$progress}
            if($command.Parameters.ContainsKey('RunDirectory')){$parameters.RunDirectory=$RunDirectory}
            $outputs=@(& $command @parameters)
            if($outputs.Count -ne 1){throw ('CompanionRunnerMustReturnOneSummary: '+$selection.Name)}
            $summary=$outputs[0]
            $summaries.Add($summary)
            Write-WorkspaceJson (Join-Path $RunDirectory ($selected.ToLowerInvariant()+'-suite.json')) $summary
            if($selected -eq 'Core' -and ($summary.Partial -or $summary.Incomplete)){
                # Filtered or stopped development run: not qualification evidence, so the full-run evidence assertion is skipped.
                $state.Task+=if($summary.Incomplete){" [INCOMPLETE: $($summary.StoppedAt)]"}else{' [PARTIAL: case filter]'}
                Write-WorkspaceJson $statusPath $state
            }elseif($selected -eq 'Core' -and !$summary.Failed){& (Join-Path $PSScriptRoot 'Assert-CoreIntegrationEvidence.ps1') -Summary $summary}
            if($parallelCompanions -and ($summary.Failed -or $summary.Partial -or $summary.Incomplete)){throw 'CompanionFanoutRequiresSuccessfulCompleteCore'}
        }
        if($parallelCompanions){
            Import-Module (Join-Path $PSScriptRoot 'lib/CiCompanionWorkers.psm1')
            $corePassed=$state.Passed;$coreFailed=$state.Failed
            $children=@(Invoke-QuietCiCompanionWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -CoreSummary $summary -Selections @($selections|Where-Object Name -CNE Core) -SkipTty:$SkipTty -ExpectedRuntimeIdentifier $ExpectedRuntimeIdentifier -MaxConcurrency ([Math]::Min(2,$MaxConcurrency)) -OnProgress {
                param($passed,$failed)
                $state.Case='Core accepted; independent companion suites running';$state.Passed=$corePassed+$passed;$state.Failed=$coreFailed+$failed
                Write-WorkspaceJson $statusPath $state
            })
            foreach($child in $children){foreach($summary in $child.Suites){$summaries.Add($summary)}}
        }
    }
    if($Profiler){
        if($Suite -notin @('Core','All','Integration')){throw 'ProfilerRequiresCoreIntegration'}
        $state.Project='FrenchExDev2.QuietCli.Core.PoSh';$state.ProjectDirectory=Join-Path $WorkspaceRoot $state.Project;$state.Task='Core PowerShell and CLR profiling';$state.Case='Attaching profilers to owned targets';Write-WorkspaceJson $statusPath $state
        $profiling=& (Join-Path $PSScriptRoot 'Invoke-CoreProfiling.ps1') -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -ProfilerModulePath $ProfilerModulePath -ClrProfilerPath $ClrProfilerPath
    }
    $state.State=if($state.Failed){'Failed'}else{'Success'}
}catch{$state.State='Crash';$state.Error=$_.ToString();$state.Failed++;Write-WorkspaceJson (Join-Path $RunDirectory 'worker-failure.json') @{Message=$_.Exception.Message;Stack=$_.ScriptStackTrace;Position=$_.InvocationInfo.PositionMessage}}
finally{
    if($sourceIdentity){
        try{
            $after=Get-QuietWorkspaceIdentity $WorkspaceRoot -IncludeBinaries:($Suite -notin @('AgentInstructions','DotNet'))
            $drift=@(foreach($before in $sourceIdentity.Projects){$current=@($after.Projects|Where-Object Name -CEQ $before.Name)[0];if($current.SourceSHA256 -cne $before.SourceSHA256){$before.Name}};if($sourceIdentity.Repository.SourceSHA256 -cne $after.Repository.SourceSHA256){'Monorepo'})
            if($drift.Count){$state.State='Failed';$state.Failed++;$state.Case='Sources changed during the run';$state.Error=$drift -join ', '}
            Write-WorkspaceJson (Join-Path $RunDirectory 'source-identity-final.json') $after
            if($Suite -notin @('Import','DotNet')){$engineIdentity=Get-QuietEngine}
            if($Suite -notin @('Import','DotNet') -and $ExpectedRuntimeIdentifier -and $engineIdentity.Engine.RuntimeIdentifier -cne $ExpectedRuntimeIdentifier){throw 'FinalEngineRuntimeMismatch'}
        }catch{$state.State='Failed';$state.Failed++;$state.Error='Build/source identity verification failed: '+$_.Exception.Message}
    }
    try{Stop-QuietEngine}catch{}
    $state.FinishedUtc=[DateTimeOffset]::UtcNow.ToString('o')
    Write-WorkspaceJson (Join-Path $RunDirectory 'summary.json') @{State=$state;Suites=$summaries.ToArray();Profiling=$profiling;EngineIdentity=$engineIdentity;HostRuntime=[Runtime.InteropServices.RuntimeInformation]::FrameworkDescription;PowerShellVersion=$PSVersionTable.PSVersion.ToString();OSArchitecture=[Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString();ProcessArchitecture=[Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture.ToString();OSDescription=[Runtime.InteropServices.RuntimeInformation]::OSDescription;MachineName=[Environment]::MachineName;ExpectedRuntimeIdentifier=$ExpectedRuntimeIdentifier;RunnerImage=$env:ImageOS;RunnerImageVersion=$env:ImageVersion}
    Write-WorkspaceJson $statusPath $state
}
if($state.State -ne 'Success'){exit 1}

}
