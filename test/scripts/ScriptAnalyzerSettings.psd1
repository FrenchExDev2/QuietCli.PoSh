@{
    # Read by scripts/lib/ScriptAnalysis.psm1. Only these four keys are accepted.
    Severity = @('Error', 'Warning')
    ExcludeRules = @(
        'PSAvoidUsingWriteHost',
        'PSUseSingularNouns',
        'PSUseBOMForUnicodeEncodedFile',
        'PSUseShouldProcessForStateChangingFunctions'
    )
    # Excluded only for Pester containers (test/scripts/**/*.Tests.ps1).
    TestExcludeRules = @(
        'PSUseDeclaredVarsMoreThanAssignments',
        'PSReviewUnusedParameter'
    )
    # Every excluded rule needs a reason of at least 20 characters.
    ExclusionReasons = @{
        PSUseDeclaredVarsMoreThanAssignments = 'Pester shares BeforeAll variables with It blocks through scopes that the analyzer cannot follow.'
        PSReviewUnusedParameter = 'Property generators and doubles must accept the parameters of their contract even when a case ignores them.'
        PSAvoidUsingWriteHost = 'Progress:, Summary: and [report] lines are the documented host protocol read by monitors and CI logs.'
        PSUseSingularNouns = 'Plural nouns are part of the published API (Get-RunTestToolPackages, Initialize-QuietTestTools); renaming breaks callers.'
        PSUseBOMForUnicodeEncodedFile = 'The repository stores PowerShell sources as UTF-8 without BOM, LF; the PowerShellSources check enforces it.'
        PSUseShouldProcessForStateChangingFunctions = 'ShouldProcess is enforced at the entry-point boundary by the ScriptShouldProcess check (RAC-PS-001), not on library functions.'
    }
}
