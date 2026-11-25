#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'RunToolCache.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'TestCaseScheduling.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop

function Import-QuietTestPester {
    <#
    .SYNOPSIS
    Loads the workspace's checksum-pinned Pester into the test process.
    .PARAMETER WorkspaceRoot
    Checkout owning the test tools cache.
    .PARAMETER ModulePath
    Manifest already resolved by the launcher.
    #>
    [CmdletBinding(DefaultParameterSetName='Workspace')]
    param(
        [Parameter(Mandatory,ParameterSetName='Workspace')][string]$WorkspaceRoot,
        [Parameter(Mandatory,ParameterSetName='Manifest')][string]$ModulePath
    )
    if(!$ModulePath -and $env:QUIETCLI_PREPARED_PESTER_MANIFEST){
        $package=Get-RunTestToolPackages -Tool pester
        $prepared=[IO.Path]::Combine((Get-QuietTestToolDirectory -WorkspaceRoot $WorkspaceRoot),$package.Name,$package.Entrypoint)
        if($env:QUIETCLI_PREPARED_PESTER_MANIFEST -ceq $prepared){$ModulePath=$prepared}
    }
    if(!$ModulePath){$ModulePath=(Initialize-QuietTestTools -WorkspaceRoot $WorkspaceRoot -Tool pester -Offline:($env:QUIETCLI_TEST_TOOLS_OFFLINE -ceq '1')).PesterModulePath}
    $expected=[IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ModulePath))
    $loaded=@(Get-Module Pester -All)
    if(!$loaded.Count){
        Import-Module $ModulePath -Global -DisableNameChecking -ErrorAction Stop
        $loaded=@(Get-Module Pester -All)
    }
    if($loaded.Count -ne 1 -or $loaded[0].Version -ne [version]'6.2.0' -or $loaded[0].ModuleBase -cne $expected){
        throw 'QuietTestPesterIdentityMismatch'
    }
    $loaded[0]
}

function Invoke-QuietPesterWithProgress {
    <#
    .SYNOPSIS
    Publishes Pester's completed test outcomes while preserving the caller's test session state.
    .PARAMETER Pester
    Module returned by Import-QuietTestPester.
    .PARAMETER Run
    Caller-bound command invoking Invoke-Pester.
    .PARAMETER OnTest
    Receives the Pester test and its Running, Passed or Failed state. Skipped tests are ignored.
    #>
    param([Parameter(Mandatory)][Management.Automation.PSModuleInfo]$Pester,[Parameter(Mandatory)][scriptblock]$Run,[Parameter(Mandatory)][scriptblock]$OnTest)
    # Pester 6.2.0 exposes this plugin injection point to its editor integrations.
    $notifyTest=$OnTest
    $before={param($Context) if(!$Context.Test.Skip){$null=& $notifyTest $Context.Test 'Running'}}.GetNewClosure()
    $after={
        param($Context)
        if(!$Context.Test.Skipped){
            $null=& $notifyTest $Context.Test $(if($Context.Test.Passed){'Passed'}else{'Failed'})
        }
    }.GetNewClosure()
    $previous=& $Pester { ,$script:additionalPlugins }
    $previousActive=Get-Variable -Name quietPesterRunActive -Scope Script -ValueOnly -ErrorAction Ignore
    try{
        $script:quietPesterRunActive=$true
        & $Pester {
            param($Before,$After)
            $plugin=New-PluginObject -Name 'QuietCliTestProgress' -EachTestSetupStart $Before -EachTestTeardownEnd $After
            $script:additionalPlugins=@($script:additionalPlugins | Where-Object {$null -ne $_})+@($plugin)
        } $before $after
        & $Run
    }finally{
        & $Pester {param($Previous) $script:additionalPlugins=$Previous} $previous
        $script:quietPesterRunActive=$previousActive
    }
}

function Invoke-QuietPesterCaseTable {
    <#
    .SYNOPSIS
    Runs the cases of a focused PowerShell test suite with Pester.
    .PARAMETER WorkspaceRoot
    Workspace supplying the pinned Pester build.
    .PARAMETER Suite
    Pester Describe name for the focused suite.
    .PARAMETER Cases
    Ordered table of case names and assertion script blocks.
    .PARAMETER InvokePester
    Caller-bound invocation receiving the Pester configuration.
    .PARAMETER OnProgress
    Receives the case name, state, passed and failed totals, and an optional failure message.
    .PARAMETER PesterModulePath
    Pinned manifest supplied by the parent to an isolated fixture checkout.
    #>
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$Suite,
        [Parameter(Mandatory)][Collections.IDictionary]$Cases,[Parameter(Mandatory)][scriptblock]$InvokePester,
        [scriptblock]$OnProgress,[string]$PesterModulePath
    )
    $counts=@{Passed=0;Failed=0}
    $results=[Collections.Generic.List[object]]::new()
    if(Get-Variable -Name quietPesterRunActive -Scope Script -ValueOnly -ErrorAction Ignore){
        # A focused suite can also supply assertions inside an owning It. Pester's runtime is already active on that stack.
        foreach($entry in $Cases.GetEnumerator()){
            if($OnProgress){$null=& $OnProgress $entry.Key 'Running' $counts.Passed $counts.Failed}
            $state='Passed';$failure=$null
            try{$null=& $InvokePester $null $entry.Value}catch{$state='Failed';$failure=$_}
            $counts[$state]++
            $results.Add([pscustomobject]@{Name=$entry.Key;State=$state;Error=$failure.Exception.Message;Stack=$failure.ScriptStackTrace})
            if($OnProgress){$null=& $OnProgress $entry.Key $state $counts.Passed $counts.Failed $failure.Exception.Message}
        }
    }else{
        $pester=if($PesterModulePath){Import-QuietTestPester -ModulePath $PesterModulePath}else{Import-QuietTestPester -WorkspaceRoot $WorkspaceRoot}
        $run=Invoke-QuietPesterCases -Pester $pester -Name $Suite -Cases $Cases -Selection @($Cases.Keys) -InvokePester $InvokePester -OnTest {
            param($test,$state)
            if($state -cin @('Passed','Failed')){$counts[$state]++}
            if($OnProgress){
                $message=if($state -ceq 'Failed' -and $test.ErrorRecord.Count){$test.ErrorRecord[0].Exception.Message}
                $null=& $OnProgress $test.Data.CaseName $state $counts.Passed $counts.Failed $message
            }
        }
        foreach($test in $run.Tests){
            $failure=$test.ErrorRecord | Select-Object -First 1
            $results.Add([pscustomobject]@{Name=$test.Data.CaseName;State=$test.Result;Error=$failure.Exception.Message;Stack=$failure.ScriptStackTrace})
        }
    }
    [pscustomobject]@{Passed=$counts.Passed;Failed=$counts.Failed;Cases=$results.ToArray()}
}

function Invoke-QuietPesterCases {
    <#
    .SYNOPSIS
    Registers each existing companion case as its own Pester test and reports its result in execution order.
    .PARAMETER Pester
    Module returned by Import-QuietTestPester.
    .PARAMETER Name
    Pester Describe name for this group of cases.
    .PARAMETER Cases
    Case name to script block map prepared in the owning suite.
    .PARAMETER Selection
    Ordered names to register from Cases.
    .PARAMETER InvokePester
    Suite-bound invocation receiving the Pester configuration. Keeps access to private fixtures and functions.
    .PARAMETER OnTest
    Receives the Pester test and its observed state.
    .PARAMETER StopOnFirstFailure
    Stops scheduling tests in this group after its first failure.
    #>
    param(
        [Parameter(Mandatory)][Management.Automation.PSModuleInfo]$Pester,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][Collections.IDictionary]$Cases,
        [Parameter(Mandatory)][AllowEmptyCollection()][string[]]$Selection,
        [Parameter(Mandatory)][scriptblock]$InvokePester,
        [Parameter(Mandatory)][scriptblock]$OnTest,
        [switch]$StopOnFirstFailure
    )
    if(!$Selection.Count){return}
    $invoke=$InvokePester
    $entries=@(foreach($caseName in $Selection){@{CaseName=$caseName;CaseBody=$Cases[$caseName]}})
    $configuration=Pester\New-PesterConfiguration
    $configuration.Run.PassThru=$true
    $configuration.Output.Verbosity='None'
    # Companion fixtures own their temporary paths and do not use TestDrive or TestRegistry.
    $configuration.TestDrive.Enabled=$false
    $configuration.TestRegistry.Enabled=$false
    if($StopOnFirstFailure){$configuration.Run.SkipRemainingOnFailure='Run'}
    $configuration.Run.Container=Pester\New-PesterContainer -ScriptBlock {
        param($SuiteName,$Entries)
        $tests=$Entries
        Describe $SuiteName {
            It '<CaseName>' -ForEach $tests { $null=& $CaseBody }
        }
    } -Data @{SuiteName=$Name;Entries=$entries}
    $result=Invoke-QuietPesterWithProgress -Pester $Pester -Run {& $invoke $configuration} -OnTest $OnTest
    if($null -eq $result -or $result.FailedBlocksCount -or $result.FailedContainersCount -or $result.TotalCount -ne $Selection.Count){
        throw ('QuietPesterCaseRunIncomplete: '+$Name)
    }
    $result
}

function Invoke-QuietPesterCompanionPlan {
    <#
    .SYNOPSIS
    Executes an existing companion plan using Pester and the isolated-case scheduler.
    .PARAMETER WorkspaceRoot
    Verified checkout containing the pinned tools and the child worker.
    .PARAMETER RunDirectory
    Owned companion report directory.
    .PARAMETER Suite
    Name of the declared companion suite.
    .PARAMETER Plan
    Validated execution plan containing the selected cases in order.
    .PARAMETER Cases
    Original case name to script block map.
    .PARAMETER Metadata
    Test kind and dependencies by case name.
    .PARAMETER InvokePester
    Suite-bound invocation receiving the Pester configuration.
    .PARAMETER OnProgress
    Receives case name, state and cumulative passed and failed totals.
    #>
    param(
        [Parameter(Mandatory)][string]$WorkspaceRoot,[Parameter(Mandatory)][string]$RunDirectory,
        [Parameter(Mandatory)][string]$Suite,[Parameter(Mandatory)]$Plan,
        [Parameter(Mandatory)][Collections.IDictionary]$Cases,[Parameter(Mandatory)][Collections.IDictionary]$Metadata,
        [Parameter(Mandatory)][scriptblock]$InvokePester,[scriptblock]$OnProgress
    )
    $caseWorker=$env:QUIETCLI_TEST_CASE_WORKER -ceq '1'
    $stopOnFirst=$env:QUIETCLI_TEST_STOP_ON_FIRST_FAILURE -ceq '1'
    $notifyProgress=$OnProgress
    $counts=@{Passed=0;Failed=0}
    $results=[Collections.Generic.List[object]]::new()
    $batches=[Collections.Generic.List[object]]::new()
    $pester=$null
    for($index=0;$index -lt $Plan.Stages.Count;$index++){
        if($stopOnFirst -and $counts.Failed){break}
        $stage=$Plan.Stages[$index]
        if($stage.Mode -ceq 'IsolatedProcess' -and !$caseWorker){
            $batch=Invoke-QuietTestCaseWorkers -WorkspaceRoot $WorkspaceRoot -RunDirectory $RunDirectory -Cases $stage.Cases.ToArray() -SuiteName $Suite -MaxConcurrency $Plan.MaxConcurrency -StopOnFirstFailure:$stopOnFirst -SkipTty:($env:QUIETCLI_TEST_SKIP_TTY -ceq '1') -ExpectedRuntimeIdentifier $env:QUIETCLI_TEST_EXPECT_RID -OnCase {
                param($name,$state)
                if($state -cin @('Passed','Failed')){$counts[$state]++}
                if($notifyProgress){$null=& $notifyProgress ('['+$Metadata[$name].TestKind+'] '+$name) $state $counts.Passed $counts.Failed}
            }
            foreach($item in $batch.Cases){
                $item | Add-Member NoteProperty TestKind $Metadata[$item.Name].TestKind
                $item | Add-Member NoteProperty Dependencies @($Metadata[$item.Name].Dependencies)
                $results.Add($item)
            }
            $batches.Add($batch)
            continue
        }

        # Group consecutive in-process stages in one Pester run without changing their order.
        $selected=[ordered]@{}
        foreach($planned in $stage.Cases){$selected.Add($planned.Name,$planned)}
        while($index+1 -lt $Plan.Stages.Count -and $Plan.Stages[$index+1].Mode -cne 'IsolatedProcess'){
            $index++
            foreach($planned in $Plan.Stages[$index].Cases){$selected.Add($planned.Name,$planned)}
        }
        if(!$pester){$pester=Import-QuietTestPester -WorkspaceRoot $WorkspaceRoot}
        $run=Invoke-QuietPesterCases -Pester $pester -Name $Suite -Cases $Cases -Selection @($selected.Keys) -InvokePester $InvokePester -StopOnFirstFailure:$stopOnFirst -OnTest {
            param($test,$state)
            $name=$test.Data.CaseName
            if($state -cin @('Passed','Failed')){
                $counts[$state]++
                if(!$caseWorker){
                    $receipt=[IO.Path]::Combine($RunDirectory,'core-cases',('pester-'+$selected[$name].Index),'case-result.json')
                    Write-WorkspaceJson $receipt @{Name=$name;State=$state}
                }
            }
            if($notifyProgress){$null=& $notifyProgress ('['+$Metadata[$name].TestKind+'] '+$name) $state $counts.Passed $counts.Failed}
        }
        foreach($test in $run.Tests){
            if($test.Result -cnotin @('Passed','Failed')){continue}
            $name=$test.Data.CaseName
            $results.Add([pscustomobject]@{
                Name=$name;State=$test.Result;Error=if($test.ErrorRecord.Count){$test.ErrorRecord[0].Exception.Message}
                TestKind=$Metadata[$name].TestKind;Dependencies=@($Metadata[$name].Dependencies)
                ExecutionMode=if($caseWorker){'CaseWorker'}else{$selected[$name].Mode}
            })
        }
    }
    if($results.Count -ne $counts.Passed+$counts.Failed){throw 'QuietPesterCaseProgressMismatch'}
    [pscustomobject]@{
        Passed=$counts.Passed;Failed=$counts.Failed;Skipped=$Plan.Cases-$results.Count
        StoppedAt=if($stopOnFirst -and $counts.Failed){'stopped at case '+$results.Count+' of '+$Cases.Count}
        Cases=$results.ToArray();ParallelBatches=$batches.ToArray()
    }
}

Export-ModuleMember -Function Import-QuietTestPester,Invoke-QuietPesterWithProgress,Invoke-QuietPesterCaseTable,Invoke-QuietPesterCompanionPlan
