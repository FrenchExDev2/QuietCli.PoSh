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
    )
}
