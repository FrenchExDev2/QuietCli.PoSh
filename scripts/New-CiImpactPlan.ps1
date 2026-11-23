#requires -Version 7.6
<#
.SYNOPSIS
Writes an explained selective PR/develop CI plan from the complete Git diff and XML dependencies.
.PARAMETER WorkspaceRoot
Selected checkout.
.PARAMETER SourceRoot
Optional materialized tree of Revision for reading source definitions separately from the Git checkout.
.PARAMETER Base
Immutable PR base or push-before revision; required unless the event is workflow_dispatch.
.PARAMETER Revision
Immutable workflow revision.
.PARAMETER WorkingTree
Compare the current checkout to Base, including non-ignored untracked files and the current contents of tracked files.
.PARAMETER Event
pull_request or push recompute their own selective impact plan from the diff; workflow_dispatch qualifies -Suite instead.
.PARAMETER Suite
workflow_dispatch only: companion names, as items or comma-separated, or all.
.PARAMETER PullRequestBody
Raw Markdown from a pull request, also accepted for a working-tree preview.
.PARAMETER OutputPath
GitHub job output file and standard report bundle.
.PARAMETER MarkdownPath
Standalone Markdown report. Relative paths are anchored in WorkspaceRoot.
.PARAMETER AsObject
Returns the plan object and allows the output path to be omitted.
.PARAMETER AsYaml
Returns the plan as YAML and allows the output path to be omitted.
#>
[CmdletBinding(SupportsShouldProcess,DefaultParameterSetName='Revision')]
param(
    [string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),
    [Parameter(ParameterSetName='Revision')][ValidateNotNullOrWhiteSpace()][string]$SourceRoot,
    [ValidatePattern('\A[a-f0-9]{40}\z')][string]$Base,
    [Parameter(Mandatory,ParameterSetName='Revision')][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,
    [Parameter(Mandatory,ParameterSetName='WorkingTree')][switch]$WorkingTree,
    [Parameter(ParameterSetName='Revision')][ValidateSet('pull_request','push','workflow_dispatch')][string]$Event='pull_request',
    [Parameter(ParameterSetName='Revision')][string[]]$Suite,
    [AllowNull()][AllowEmptyString()][string]$PullRequestBody,
    [AllowNull()][AllowEmptyString()][string]$OutputPath,
    [ValidateNotNullOrWhiteSpace()][string]$MarkdownPath,
    [switch]$AsObject,
    [switch]$AsYaml
)
$ErrorActionPreference='Stop'
if($AsObject -and $AsYaml){throw 'CiImpactOutputFormatConflict: use either -AsObject or -AsYaml.'}
$writeFiles=![string]::IsNullOrWhiteSpace($OutputPath)
if(!$writeFiles -and !$MarkdownPath -and !$AsObject -and !$AsYaml){throw 'CiImpactOutputPathRequired: supply -OutputPath or -MarkdownPath, or use -AsObject or -AsYaml.'}
$localPreview=[bool]$WorkingTree
if(!$localPreview -and !$Revision){throw 'CiImpactRevisionRequired'}
$dispatch=$Event -ceq 'workflow_dispatch'
if($dispatch -and $Base){throw 'CiImpactDispatchTakesNoBase'}
if(!$dispatch -and !$Base){throw 'CiImpactBaseRequired'}
if(!$dispatch -and $PSBoundParameters.ContainsKey('Suite')){throw 'CiImpactSuiteRequiresDispatch'}
if($Event -cne 'pull_request' -and $PSBoundParameters.ContainsKey('PullRequestBody')){throw 'CiImpactBodyRequiresPullRequest'}
$candidate=if($localPreview){'working-tree'}else{$Revision}
$action=if($writeFiles -or $MarkdownPath){'Resolve changed suites and save the CI execution plan'}else{'Resolve changed suites'}
if(!$PSCmdlet.ShouldProcess($candidate,$action)){return}
$WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot,$PWD.ProviderPath)
$sourceTree=if($SourceRoot){[IO.Path]::GetFullPath($SourceRoot,$WorkspaceRoot)}else{$WorkspaceRoot}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImpact.psm1')) -ErrorAction Stop -DisableNameChecking
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CompanionWorkflows.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiPlanReport.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/ScriptsImpact.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/PullRequestChecklist.psm1')) -DisableNameChecking -ErrorAction Stop
if($dispatch){
    # A manual run qualifies the requested companions in full; it never reads a diff.
    $plan=Get-QuietCiDispatchImpact -WorkspaceRoot $sourceTree -Suite $Suite
    $baseLabel='manual-dispatch'
}else{
    $baseLabel=$Base
    $state=@{Text=[Text.StringBuilder]::new()}
    $diffArguments=@('diff','--no-renames','--name-only','-z',$Base)
    $diffArguments=if($localPreview){@('--no-optional-locks')+$diffArguments+@('--')}else{$diffArguments+@($Revision,'--')}
    $appendPaths={param($e,$s)if($e.Stream -eq 'stdout'){if($s.Text.Length){[void]$s.Text.Append([char]10)};[void]$s.Text.Append($e.Text)}}
    $diff=Invoke-CiProcess -FilePath git -ArgumentList $diffArguments -WorkingDirectory $WorkspaceRoot -State $state -OnOutput $appendPaths
    if($diff.Outcome -ne 'Success'){throw 'CiImpactCompleteDiffRequired'}
    $paths=@($state.Text.ToString().Split([char]0,[StringSplitOptions]::RemoveEmptyEntries))
    if($localPreview){
        [void]$state.Text.Clear()
        $untracked=Invoke-CiProcess -FilePath git -ArgumentList @('--no-optional-locks','ls-files','-z','--others','--exclude-standard','--') -WorkingDirectory $WorkspaceRoot -State $state -OnOutput $appendPaths
        if($untracked.Outcome -ne 'Success'){throw 'CiImpactCompleteUntrackedListRequired'}
        $paths+=@($state.Text.ToString().Split([char]0,[StringSplitOptions]::RemoveEmptyEntries))
        $paths=@($paths | Select-Object -Unique)
    }
    $previous=@{}
    foreach($path in $paths|Where-Object {$_ -match '\.(props|targets|csproj)$' -or $_ -ceq 'test/scripts/mutation.targets.psd1'}){
        $content=@{Text=[Text.StringBuilder]::new()}
        $observed=Invoke-CiProcess -FilePath git -ArgumentList @('show',($Base+':'+$path)) -WorkingDirectory $WorkspaceRoot -State $content -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Text.AppendLine($e.Text)}}
        if($observed.Outcome -eq 'Success'){$previous[$path]=$content.Text.ToString()}
    }
    $plan=Get-QuietCiImpact -WorkspaceRoot $sourceTree -ChangedPaths $paths -PreviousFiles $previous
}
$selection=Read-QuietPullRequestChecklist $PullRequestBody
Add-QuietCiPullRequestSelection -Plan $plan -WorkspaceRoot $sourceTree -Options $selection.Selected
# Script changes alone run only the script tests and mutation targets they reach; the full tooling runs them all.
$scriptsImpact=if(!$plan.RunTooling -and @($plan.ScriptPaths).Count){
    Get-QuietScriptsImpact -WorkspaceRoot $sourceTree -ChangedPaths @($plan.ScriptPaths) -PreviousMutationCatalogue $previous['test/scripts/mutation.targets.psd1']
}
$scope=if($plan.RunTooling){'full'}elseif($scriptsImpact -and ($scriptsImpact.TestFiles.Count -or $scriptsImpact.MutationTargets.Count)){'scripts'}else{'none'}
$plan|Add-Member -NotePropertyName ToolingScope -NotePropertyValue $scope
if($scriptsImpact){
    $plan.Reasons=@($plan.Reasons)+@(foreach($reason in $scriptsImpact.Reasons){
        $source,$why=$reason.Reason -split ': ',2
        [pscustomobject]@{Input=$source;Package=$null;Project=$reason.Name;Companion='Scripts';Action=$reason.Selection;Reason=$why}
    })
}
$profiles=@(Get-QuietCompanionProfiles $sourceTree)
$rows=@(foreach($name in $plan.FullSuites){
    $profile=@($profiles|Where-Object Suite -CEQ $name)
    if($profile.Count -ne 1){throw ('CiPlanProfileMissing: '+$name)}
    $modules=@(Get-QuietWorkspaceBuildSelection $sourceTree -Suite $name)
    $roots=@(Get-QuietWorkspaceProjects $sourceTree|Where-Object Name -CIn $modules|ForEach-Object {$_.Path+'/'})
    $projects=@($plan.BuildProjects|Where-Object {$path=$_;@($roots|Where-Object {$path.StartsWith($_,[StringComparison]::Ordinal)}).Count})
    # A Preview request requires an unrestricted Core build, including on a dependency-only change.
    $preview=$name -ceq 'Core' -and $plan.RunPreview
    if($preview){$projects=@()}
    [ordered]@{suite=$name;solution_path=$profile[0].SolutionPath;source_path=$profile[0].SourcePath;test_path=$profile[0].TestPath;collect_performance=$profile[0].CollectPerformance;run_preview=$preview;build_projects_json=(ConvertTo-Json -InputObject @($projects) -Compress)}
})
$values="suite=$($plan.Suite)`nrun_products=$($plan.RunProducts.ToString().ToLowerInvariant())`nrun_tooling=$(($scope -cne 'none').ToString().ToLowerInvariant())`n"
$outputs=@{
    # Every fully qualified suite runs on a Linux image chain that the companions workflow warms once per RID.
    image_suites=(ConvertTo-Json -InputObject @($plan.FullSuites) -Compress)
    matrix=(@{include=$rows}|ConvertTo-Json -Depth 6 -Compress)
    smoke_suites=(ConvertTo-Json -InputObject @($plan.SmokeSuites) -Compress)
    run_smokes=($plan.SmokeSuites.Count -gt 0).ToString().ToLowerInvariant()
    run_distribution=$plan.RunDistribution.ToString().ToLowerInvariant()
    run_readytorun=$plan.RunReadyToRun.ToString().ToLowerInvariant()
    pr_ci_options=ConvertTo-Json -InputObject $selection.Selected -Compress
    # The generated-layout campaign is skipped only when script tests are the whole selected work.
    run_layout=!($scope -ceq 'scripts' -and !$plan.RunProducts -and !$plan.SmokeSuites.Count -and !$plan.RunDistribution -and !$plan.RunReadyToRun)
    tooling_scope=$scope
    script_tests=$(if($scope -ceq 'full' -or ($scriptsImpact -and $scriptsImpact.AllTests)){'all'}elseif($scriptsImpact){ConvertTo-Json -InputObject @($scriptsImpact.TestFiles) -Compress}else{'[]'})
    script_mutation_targets=$(if($scope -ceq 'full' -or ($scriptsImpact -and $scriptsImpact.AllTargets)){'all'}elseif($scriptsImpact){ConvertTo-Json -InputObject @($scriptsImpact.MutationTargets) -Compress}else{'[]'})
}
$outputs.run_layout=$outputs.run_layout.ToString().ToLowerInvariant()
if($localPreview -or $MarkdownPath){
    $scriptSelection=if($scope -cne 'none'){
        Resolve-QuietScriptsCiSelection -WorkspaceRoot $sourceTree -Scope $scope -Tests $outputs.script_tests -Targets $outputs.script_mutation_targets
    }
    $plan|Add-Member -NotePropertyMembers ([ordered]@{
        RunScriptTooling=$scope -cne 'none'
        ScriptTests=[string[]]@($scriptSelection.TestFiles | Where-Object {$_})
        ScriptMutationTargets=[string[]]@($scriptSelection.MutationTargets | Where-Object {$_})
        ScriptTestsRequireBuild=[bool]$scriptSelection.RequiresBuild
    })
}
if($MarkdownPath){
    $plan|Add-Member -NotePropertyName RunLayout -NotePropertyValue ($outputs.run_layout -ceq 'true')
    $MarkdownPath=[IO.Path]::GetFullPath($MarkdownPath,$WorkspaceRoot)
    Write-QuietCiPlanReport -Plan $plan -Base $baseLabel -Revision $candidate -MarkdownPath $MarkdownPath -Confirm:$false
}
$delivery=if($AsYaml){
    # The companion catalogue has already loaded the pinned YamlDotNet assembly.
    # Project the PowerShell object to ordered mappings and sequences before serialization.
    $json=ConvertTo-Json -InputObject $plan -Depth 12 -Compress -WarningAction Stop
    $mapping=ConvertFrom-Json -InputObject $json -AsHashtable -DateKind String
    [YamlDotNet.Serialization.SerializerBuilder]::new().WithQuotingNecessaryStrings($true).Build().Serialize($mapping)
}else{$plan}
if($writeFiles){
    $summaryPath=if(!$localPreview){$env:GITHUB_STEP_SUMMARY}
    $directory=[IO.Path]::Combine($WorkspaceRoot,'artifacts/ci-plan')
    Write-QuietCiPlanReport -Plan $plan -Base $baseLabel -Revision $candidate -Directory $directory -SummaryPath $summaryPath -Confirm:$false
    [IO.File]::AppendAllText($OutputPath,$values,[Text.UTF8Encoding]::new($false))
    foreach($key in @($outputs.Keys|Sort-Object)){[IO.File]::AppendAllText($OutputPath,($key+'='+$outputs[$key]+[char]10),[Text.UTF8Encoding]::new($false))}
}
if($writeFiles -or $AsObject -or $AsYaml){$delivery}
