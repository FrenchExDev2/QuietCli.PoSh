#requires -Version 7.6
<#
.SYNOPSIS
Writes an explained selective PR/develop CI plan from the complete Git diff and XML dependencies.
.PARAMETER WorkspaceRoot
Selected checkout.
.PARAMETER Base
Immutable PR base or push-before revision; required unless the event is workflow_dispatch.
.PARAMETER Revision
Immutable workflow revision.
.PARAMETER Event
pull_request or push recompute their own selective impact plan from the diff; workflow_dispatch qualifies -Suite instead.
.PARAMETER Suite
workflow_dispatch only: companion names, as items or comma-separated, or all.
.PARAMETER OutputPath
GitHub job output file.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[ValidatePattern('\A[a-f0-9]{40}\z')][string]$Base,[Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,[ValidateSet('pull_request','push','workflow_dispatch')][string]$Event='pull_request',[string[]]$Suite,[Parameter(Mandatory)][string]$OutputPath)
$ErrorActionPreference='Stop'
$dispatch=$Event -ceq 'workflow_dispatch'
if($dispatch -and $Base){throw 'CiImpactDispatchTakesNoBase'}
if(!$dispatch -and !$Base){throw 'CiImpactBaseRequired'}
if(!$dispatch -and $PSBoundParameters.ContainsKey('Suite')){throw 'CiImpactSuiteRequiresDispatch'}
if(!$PSCmdlet.ShouldProcess($Revision,'Resolve changed suites and save the CI execution plan')){return}
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImpact.psm1')) -ErrorAction Stop -DisableNameChecking
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CompanionWorkflows.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiPlanReport.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/ScriptsImpact.psm1')) -DisableNameChecking -ErrorAction Stop
if($dispatch){
    # A manual run qualifies the requested companions in full; it never reads a diff.
    $plan=Get-QuietCiDispatchImpact -WorkspaceRoot $WorkspaceRoot -Suite $Suite
    $baseLabel='manual-dispatch'
}else{
    $baseLabel=$Base
    $state=@{Text=[Text.StringBuilder]::new()}
    $diff=Invoke-CiProcess -FilePath git -ArgumentList @('diff','--no-renames','--name-only','-z',$Base,$Revision,'--') -WorkingDirectory $WorkspaceRoot -State $state -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Text.Append($e.Text)}}
    if($diff.Outcome -ne 'Success'){throw 'CiImpactCompleteDiffRequired'}
    $paths=@($state.Text.ToString().Split([char]0,[StringSplitOptions]::RemoveEmptyEntries))
    $previous=@{}
    foreach($path in $paths|Where-Object {$_ -match '\.(props|targets|csproj)$'}){
        $content=@{Text=[Text.StringBuilder]::new()}
        $observed=Invoke-CiProcess -FilePath git -ArgumentList @('show',($Base+':'+$path)) -WorkingDirectory $WorkspaceRoot -State $content -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Text.AppendLine($e.Text)}}
        if($observed.Outcome -eq 'Success'){$previous[$path]=$content.Text.ToString()}
    }
    $plan=Get-QuietCiImpact -WorkspaceRoot $WorkspaceRoot -ChangedPaths $paths -PreviousFiles $previous
}
# Script changes alone run only the script tests and mutation targets they reach; the full tooling runs them all.
$scriptsImpact=if(!$plan.RunTooling -and @($plan.ScriptPaths).Count){Get-QuietScriptsImpact -WorkspaceRoot $WorkspaceRoot -ChangedPaths @($plan.ScriptPaths)}
$scope=if($plan.RunTooling){'full'}elseif($scriptsImpact -and ($scriptsImpact.TestFiles.Count -or $scriptsImpact.MutationTargets.Count)){'scripts'}else{'none'}
$plan|Add-Member -NotePropertyName ToolingScope -NotePropertyValue $scope
if($scriptsImpact){
    $plan.Reasons=@($plan.Reasons)+@(foreach($reason in $scriptsImpact.Reasons){
        $source,$why=$reason.Reason -split ': ',2
        [pscustomobject]@{Input=$source;Package=$null;Project=$reason.Name;Companion='Scripts';Action=$reason.Selection;Reason=$why}
    })
}
$profiles=@(Get-QuietCompanionProfiles $WorkspaceRoot)
$rows=@(foreach($name in $plan.FullSuites){
    $profile=@($profiles|Where-Object Suite -CEQ $name)
    if($profile.Count -ne 1){throw ('CiPlanProfileMissing: '+$name)}
    $modules=@(Get-QuietWorkspaceBuildSelection $WorkspaceRoot -Suite $name)
    $roots=@(Get-QuietWorkspaceProjects $WorkspaceRoot|Where-Object Name -CIn $modules|ForEach-Object {$_.Path+'/'})
    $projects=@($plan.BuildProjects|Where-Object {$path=$_;@($roots|Where-Object {$path.StartsWith($_,[StringComparison]::Ordinal)}).Count})
    [ordered]@{suite=$name;solution_path=$profile[0].SolutionPath;source_path=$profile[0].SourcePath;test_path=$profile[0].TestPath;collect_performance=$profile[0].CollectPerformance;build_projects_json=(ConvertTo-Json -InputObject @($projects) -Compress)}
})
$directory=[IO.Path]::Combine($WorkspaceRoot,'artifacts/ci-plan');[void][IO.Directory]::CreateDirectory($directory)
Write-QuietCiPlanReport -Plan $plan -Base $baseLabel -Revision $Revision -Directory $directory -SummaryPath $env:GITHUB_STEP_SUMMARY -Confirm:$false
$values="suite=$($plan.Suite)`nrun_products=$($plan.RunProducts.ToString().ToLowerInvariant())`nrun_tooling=$(($scope -cne 'none').ToString().ToLowerInvariant())`n"
[IO.File]::AppendAllText($OutputPath,$values,[Text.UTF8Encoding]::new($false))
$outputs=@{
    # Every fully qualified suite runs on a Linux image chain that the companions workflow warms once per RID.
    image_suites=(ConvertTo-Json -InputObject @($plan.FullSuites) -Compress)
    matrix=(@{include=$rows}|ConvertTo-Json -Depth 6 -Compress)
    smoke_suites=(ConvertTo-Json -InputObject @($plan.SmokeSuites) -Compress)
    run_smokes=($plan.SmokeSuites.Count -gt 0).ToString().ToLowerInvariant()
    run_distribution=$plan.RunDistribution.ToString().ToLowerInvariant()
    # The generated-layout campaign is skipped only when script tests are the whole selected work.
    run_layout=!($scope -ceq 'scripts' -and !$plan.RunProducts -and !$plan.SmokeSuites.Count -and !$plan.RunDistribution)
    tooling_scope=$scope
    script_tests=$(if($scope -ceq 'full' -or ($scriptsImpact -and $scriptsImpact.AllTests)){'all'}elseif($scriptsImpact){ConvertTo-Json -InputObject @($scriptsImpact.TestFiles) -Compress}else{'[]'})
    script_mutation_targets=$(if($scope -ceq 'full' -or ($scriptsImpact -and $scriptsImpact.AllTargets)){'all'}elseif($scriptsImpact){ConvertTo-Json -InputObject @($scriptsImpact.MutationTargets) -Compress}else{'[]'})
}
$outputs.run_layout=$outputs.run_layout.ToString().ToLowerInvariant()
foreach($key in @($outputs.Keys|Sort-Object)){[IO.File]::AppendAllText($OutputPath,($key+'='+$outputs[$key]+[char]10),[Text.UTF8Encoding]::new($false))}
$plan
