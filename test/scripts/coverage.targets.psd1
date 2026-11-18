# Libraries whose line coverage Invoke-ScriptsTests.ps1 -Coverage measures (paths relative to the scripts root).
# Threshold is the minimum JaCoCo line coverage percentage over all targets; raise it, never lower it.
@{
    Threshold = 80
    Paths = @(
        'lib/ScriptsTests.psm1'
        'lib/RunToolCache.psm1'
        'lib/ScriptAnalysis.psm1'
        'lib/ScriptMutation.psm1'
        'lib/ScriptMutators.psm1'
        'lib/ScriptsInventory.psm1'
        'lib/CiImpact.psm1'
        'lib/CiCompanions.psm1'
        'lib/CompanionWorkflows.psm1'
        'lib/CiPlanResults.psm1'
        'lib/ScriptsImpact.psm1'
        'lib/GitHubActionReferences.psm1'
        'lib/GitHubActionReleases.psm1'
        'lib/GitHubActionUpdates.psm1'
        'lib/Update-GitHubActions.psm1'
        'lib/PerformanceStatistics.psm1'
        'lib/PerformanceWorkloads.psm1'
        'lib/PerformanceCharts.psm1'
        'lib/New-CorePerformanceReport.psm1'
        'lib/MergedBranches.psm1'
    )
}
