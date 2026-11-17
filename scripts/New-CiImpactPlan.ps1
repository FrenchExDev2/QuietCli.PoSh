#requires -Version 7.6
<#
.SYNOPSIS
Writes an explained selective PR/develop CI plan from the complete Git diff and XML dependencies.
.PARAMETER WorkspaceRoot
Selected checkout.
.PARAMETER Base
Immutable PR base or push-before revision.
.PARAMETER Revision
Immutable workflow revision.
.PARAMETER Event
pull_request or push; each event recomputes its own selective impact plan.
.PARAMETER OutputPath
GitHub job output file.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Base,[Parameter(Mandatory)][ValidatePattern('\A[a-f0-9]{40}\z')][string]$Revision,[ValidateSet('pull_request','push')][string]$Event='pull_request',[Parameter(Mandatory)][string]$OutputPath)
if(!$PSCmdlet.ShouldProcess($Revision,'Resolve changed suites and save the CI execution plan')){return}
$ErrorActionPreference='Stop'
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/Common.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiImpact.psm1')) -ErrorAction Stop -DisableNameChecking
$state=@{Text=[Text.StringBuilder]::new()}
$diff=Invoke-CiProcess -FilePath git -ArgumentList @('diff','--no-renames','--name-only','-z',$Base,$Revision,'--') -WorkingDirectory $WorkspaceRoot -State $state -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Text.Append($e.Text)}}
if($diff.Outcome -ne 'Success'){throw 'CiImpactCompleteDiffRequired'}
$paths=@($state.Text.ToString().Split([char]0,[StringSplitOptions]::RemoveEmptyEntries))
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CompanionWorkflows.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'lib/CiPlanReport.psm1')) -DisableNameChecking -ErrorAction Stop
$previous=@{}
foreach($path in $paths|Where-Object {$_ -match '\.(props|targets|csproj)$'}){
    $content=@{Text=[Text.StringBuilder]::new()}
    $observed=Invoke-CiProcess -FilePath git -ArgumentList @('show',($Base+':'+$path)) -WorkingDirectory $WorkspaceRoot -State $content -OnOutput {param($e,$s)if($e.Stream -eq 'stdout'){[void]$s.Text.AppendLine($e.Text)}}
    if($observed.Outcome -eq 'Success'){$previous[$path]=$content.Text.ToString()}
}
$plan=Get-QuietCiImpact -WorkspaceRoot $WorkspaceRoot -ChangedPaths $paths -PreviousFiles $previous
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
Write-QuietCiPlanReport -Plan $plan -Base $Base -Revision $Revision -Directory $directory -SummaryPath $env:GITHUB_STEP_SUMMARY -Confirm:$false
$values="suite=$($plan.Suite)`nrun_products=$($plan.RunProducts.ToString().ToLowerInvariant())`nrun_tooling=$($plan.RunTooling.ToString().ToLowerInvariant())`n"
[IO.File]::AppendAllText($OutputPath,$values,[Text.UTF8Encoding]::new($false))
$outputs=@{
    # Every fully qualified suite runs on a Linux image chain that the companions workflow warms once per RID.
    image_suites=(ConvertTo-Json -InputObject @($plan.FullSuites) -Compress)
    matrix=(@{include=$rows}|ConvertTo-Json -Depth 6 -Compress)
    smoke_suites=(ConvertTo-Json -InputObject @($plan.SmokeSuites) -Compress)
    run_smokes=($plan.SmokeSuites.Count -gt 0).ToString().ToLowerInvariant()
    run_distribution=$plan.RunDistribution.ToString().ToLowerInvariant()
}
foreach($key in @($outputs.Keys|Sort-Object)){[IO.File]::AppendAllText($OutputPath,($key+'='+$outputs[$key]+[char]10),[Text.UTF8Encoding]::new($false))}
$plan
