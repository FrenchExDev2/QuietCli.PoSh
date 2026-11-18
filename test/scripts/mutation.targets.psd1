# Mutation targets of Invoke-ScriptsMutation.ps1. Module is relative to the scripts root, UnitTestFiles to test/scripts.
# Break is the minimum score (killed + timeout over valid mutants, in percent); raise it, never lower it.
# Inputs (optional) names the repository files outside scripts/ and test/scripts/ that the unit tests read, so the
# incremental cache invalidates their outcomes when those files change.
@{
    Targets = @(
        @{
            Name = 'ScriptsTests'
            Module = 'lib/ScriptsTests.psm1'
            Functions = @('ConvertTo-QuietScriptsXmlText','Protect-QuietScriptsTestResult','Get-QuietScriptsTestPlan','Get-QuietScriptsTestValue','Test-QuietScriptsPathWithin','Resolve-QuietScriptsTestPath','Get-QuietScriptsCoverageTargets','New-QuietScriptsPesterConfiguration','ConvertTo-QuietScriptsTestCount','ConvertTo-QuietScriptsTestReport','New-QuietScriptsTestStatus','Update-QuietScriptsTestStatus','Get-QuietScriptsTestExitCode','Test-QuietScriptsTestsApplicable')
            UnitTestFiles = @('unit/lib/ScriptsTests.Tests.ps1')
            Break = 80
            Equivalent = @(
                @{Function = 'Get-QuietScriptsTestValue'; Mutator = 'ConditionalExpression'; Original = '$null -ne $property'; Replacement = '$true'; Reason = 'Outside strict mode the Value of a null property reads as null, the value already held; the guard keeps strict-mode callers safe.'}
                @{Function = 'Test-QuietScriptsPathWithin'; Mutator = 'ConditionalExpression'; Original = '$IsWindows'; Replacement = '$true'; Reason = 'On Windows $IsWindows is already true, so forcing it changes nothing.'; Platform = 'Windows'}
                @{Function = 'Test-QuietScriptsPathWithin'; Mutator = 'ConditionalExpression'; Original = '$IsWindows'; Replacement = '$false'; Reason = 'Off Windows $IsWindows is already false, so forcing it changes nothing.'; Platform = 'Linux'}
            )
        }

        @{
            Name = 'ScriptAnalysis'
            Module = 'lib/ScriptAnalysis.psm1'
            # The unit tests load the pinned PSScriptAnalyzer, whose version RunToolCache fixes.
            Functions = @('Compare-QuietScriptAnalysisBaseline','Get-QuietScriptAnalysisFindingKey','Get-QuietScriptAnalysisSha256','Get-QuietScriptAnalysisFunctionName','ConvertTo-QuietScriptAnalysisFinding','ConvertTo-QuietScriptAnalysisBaseline','Read-QuietScriptAnalysisBaseline','Read-QuietScriptAnalysisSettings','Test-QuietScriptAnalysisTestContainer','Get-QuietScriptAnalysisFiles','Get-QuietScriptAnalysisCacheKey')
            UnitTestFiles = @('unit/lib/ScriptAnalysis.Tests.ps1')
            Inputs = @('scripts/lib/RunToolCache.psm1')
            Break = 80
            # Equivalent mutants: the tests cannot tell them apart, for the reason given. A stale entry fails the run.
            Equivalent = @(
                @{Function = 'Compare-QuietScriptAnalysisBaseline'; Mutator = 'ConditionalExpression'; Original = '$expected.ContainsKey($key)'; Replacement = '$true'; Reason = 'Outside strict mode a missing key reads as null, whose Count is 0; the guard only keeps the module strict-mode safe.'}
                @{Function = 'Compare-QuietScriptAnalysisBaseline'; Mutator = 'ConditionalExpression'; Original = '$actual.ContainsKey($key)'; Replacement = '$true'; Reason = 'Outside strict mode a missing key reads as null, whose Count is 0; the guard only keeps the module strict-mode safe.'}
            )
        }
        @{
            Name = 'ScriptMutation'
            Module = 'lib/ScriptMutation.psm1'
            Functions = @('Get-QuietScriptMutants','New-QuietScriptMutantSource','Get-QuietScriptMutantStatus','Get-QuietScriptMutantTimeout','Get-QuietScriptMutationFocus','Measure-QuietScriptMutationScore','Read-QuietScriptMutationTargets','Select-QuietScriptMutationEquivalents','New-QuietScriptMutationReport','ConvertTo-QuietScriptMutationMarkdown','Assert-QuietScriptMutationShards')
            UnitTestFiles = @('unit/lib/ScriptMutation.Tests.ps1','unit/lib/ScriptMutators.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'ScriptsInventory'
            Module = 'lib/ScriptsInventory.psm1'
            Functions = @('Get-QuietScriptsLibraryExports','Get-QuietScriptsTestInventory','Read-QuietScriptsTestInventoryBaseline','Compare-QuietScriptsTestInventory')
            UnitTestFiles = @('unit/lib/ScriptsInventory.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'CiImpact'
            Module = 'lib/CiImpact.psm1'
            Functions = @('Get-QuietCiImpact','Get-QuietCiDependentSmokes','Get-QuietCiDispatchImpact','Test-QuietDevelopReceipt')
            UnitTestFiles = @('unit/lib/CiImpact.Tests.ps1')
            Break = 80
            Equivalent = @(
                @{Function = 'Get-QuietCiImpact'; Mutator = 'StringLiteral'; Original = "'Stop'"; Replacement = "''"; Reason = 'Every failure in the function is a terminating throw or a -ErrorAction Stop call, so no non-terminating error reaches the preference.'}
                @{Function = 'Get-QuietCiDispatchImpact'; Mutator = 'StringLiteral'; Original = "'Stop'"; Replacement = "''"; Reason = 'Every failure in the function is a terminating throw, so no non-terminating error reaches the preference.'}
            )
        }
        @{
            # Invoke-QuietCiSuiteImage drives a container runtime; its guards are tested, its body is covered by the image workflows.
            Name = 'CiCompanions'
            Module = 'lib/CiCompanions.psm1'
            Functions = @('Get-QuietCiCompanionOrder','Read-QuietCiCompanions','Resolve-QuietCiCompanions','Get-QuietCiSuiteImagePlan','Invoke-QuietCiSuiteImages','Assert-QuietCiCompanionImages')
            UnitTestFiles = @('unit/lib/CiCompanions.Tests.ps1')
            Equivalent = @(
                @{Function = 'Invoke-QuietCiSuiteImages'; Mutator = 'StringLiteral'; Original = "'Prepare the image chains of the selected suites'"; Replacement = "''"; Reason = 'ShouldProcess action text is only shown by the host under -WhatIf or -Confirm; no result depends on it.'}
                @{Function = 'Assert-QuietCiCompanionImages'; Mutator = 'StringLiteral'; Original = "'*'"; Replacement = "''"; Reason = '.NET file enumeration treats an empty search pattern as * and returns every file.'}
            )
            # The unit tests read the real catalogue, test manifests, image contexts, module contracts and the locks those
            # contracts hash, and scan every product module for container files. Not src/**: build outputs under obj/
            # would change the key on every local build.
            Inputs = @('build/**','global.json','.github/containers/**','src/*/test/*/*.psd1','src/*/src/*/ci/**','src/*/src/*/.github/containers/**','src/*/src/*/metadata/locks/**','src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json','src/*/src/**/Dockerfile*','src/*/src/**/Containerfile*','src/*/src/**/*.Dockerfile','src/*/src/**/*.Containerfile')
            Break = 80
        }
        @{
            Name = 'CompanionWorkflows'
            Module = 'lib/CompanionWorkflows.psm1'
            Functions = @('Get-QuietCompanionProfiles','Get-QuietCompanionWorkflowDefinitions','Sync-QuietCompanionWorkflows','Assert-QuietCompanionProfile')
            UnitTestFiles = @('unit/lib/CompanionWorkflows.Tests.ps1')
            Equivalent = @(
                @{Function = 'Sync-QuietCompanionWorkflows'; Mutator = 'StringLiteral'; Original = "'Synchronize companion workflow'"; Replacement = "''"; Reason = 'ShouldProcess action text is only shown by the host under -WhatIf or -Confirm; no result depends on it.'}
            )
            # YamlDotNet is resolved through Core's dependency lock.
            Inputs = @('src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/resources/dependencies.lock.json')
            Break = 80
        }
        @{
            Name = 'CiPlanResults'
            Module = 'lib/CiPlanResults.psm1'
            Functions = @('Assert-QuietCiPlanResults')
            UnitTestFiles = @('unit/lib/CiPlanResults.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'ScriptsImpact'
            Module = 'lib/ScriptsImpact.psm1'
            Functions = @('Get-QuietScriptsTestFiles','Get-QuietScriptsImpact','Resolve-QuietScriptsCiSelection')
            UnitTestFiles = @('unit/lib/ScriptsImpact.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'ScriptMutationCache'
            Module = 'lib/ScriptMutationCache.psm1'
            Functions = @('Get-QuietScriptMutationSha256','Get-QuietScriptMutationFilesDigest','Get-QuietScriptMutationTreeFiles','Get-QuietScriptMutationTestFingerprint','Get-QuietScriptMutationSourceFingerprint','Get-QuietScriptMutationSourceFiles','Get-QuietScriptMutationInputsFingerprint','Get-QuietScriptMutationInputFiles','Get-QuietScriptMutationTargetFingerprint','Get-QuietScriptMutantCacheKeys','Get-QuietScriptMutantCachePath','Read-QuietScriptMutationCacheDocument','Get-QuietScriptMutationCacheValue','Read-QuietScriptMutantCache','Write-QuietScriptMutantCache','Get-QuietScriptMutationBaselineKey','Read-QuietScriptMutationBaseline','Write-QuietScriptMutationBaseline','Remove-QuietScriptMutantCacheUnused')
            UnitTestFiles = @('unit/lib/ScriptMutationCache.Tests.ps1')
            Break = 80
            Equivalent = @(
                @{Function = 'Get-QuietScriptMutationTargetFingerprint'; Mutator = 'ConditionalExpression'; Original = '$Target.Contains(''Inputs'')'; Replacement = '$true'; Reason = 'Outside strict mode an absent Inputs key reads as null, which the empty-pattern filter drops; the guard keeps strict-mode callers safe.'}
                @{Function = 'Get-QuietScriptMutationTargetFingerprint'; Mutator = 'ConditionalExpression'; Original = '$Target.PSObject.Properties[''Inputs'']'; Replacement = '$true'; Reason = 'Outside strict mode an absent Inputs property reads as null, which the empty-pattern filter drops; the guard keeps strict-mode callers safe.'}
                @{Function = 'Get-QuietScriptMutationCacheValue'; Mutator = 'ConditionalExpression'; Original = '$property'; Replacement = '$true'; Reason = 'Outside strict mode the Value of an absent property reads as null, the same as the guarded branch; the guard keeps the reader strict-mode safe.'}
                @{Function = 'Read-QuietScriptMutationCacheDocument'; Mutator = 'BlockStatement'; Original = '{$null}'; Replacement = '{}'; Reason = 'A failed read assigns nothing, which leaves the document null exactly as the catch value does.'}
            )
        }
        @{
            # Start, the worker loop and the success path of a job need real processes: integration/lib covers them.
            Name = 'ScriptMutationSlot'
            Module = 'lib/ScriptMutationSlot.psm1'
            Functions = @('Test-QuietScriptsMutationSlotPester','Test-QuietScriptsMutationSlotParent','Restore-QuietScriptsMutationSlotState','Submit-QuietScriptsMutationJob','Receive-QuietScriptsMutationJob','Wait-QuietScriptsMutationJob','Stop-QuietScriptsMutationSlot')
            UnitTestFiles = @('unit/lib/ScriptMutationSlot.Tests.ps1')
            Break = 80
            Equivalent = @(
                @{Function = 'Restore-QuietScriptsMutationSlotState'; Mutator = 'ConditionalExpression'; Original = '$IsWindows'; Replacement = '$true'; Reason = 'On Windows $IsWindows is already true, so forcing it changes nothing.'; Platform = 'Windows'}
                @{Function = 'Restore-QuietScriptsMutationSlotState'; Mutator = 'BlockStatement'; Original = '{[StringComparison]::Ordinal}'; Replacement = '{}'; Reason = 'The Ordinal branch only runs off Windows; on Windows it is unreachable.'; Platform = 'Windows'}
                @{Function = 'Restore-QuietScriptsMutationSlotState'; Mutator = 'ConditionalExpression'; Original = '$IsWindows'; Replacement = '$false'; Reason = 'Off Windows $IsWindows is already false, so forcing it changes nothing.'; Platform = 'Linux'}
                @{Function = 'Restore-QuietScriptsMutationSlotState'; Mutator = 'BlockStatement'; Original = '{[StringComparison]::OrdinalIgnoreCase}'; Replacement = '{}'; Reason = 'The OrdinalIgnoreCase branch only runs on Windows; elsewhere it is unreachable.'; Platform = 'Linux'}
                @{Function = 'Restore-QuietScriptsMutationSlotState'; Mutator = 'ConditionalExpression'; Original = '!$State.Environment.ContainsKey([string]$entry.Key)'; Replacement = '$true'; Reason = 'Deleting a captured variable too is undone by the restore loop that follows, which sets every captured variable back.'}
                @{Function = 'Restore-QuietScriptsMutationSlotState'; Mutator = 'ConditionalExpression'; Original = '[Environment]::GetEnvironmentVariable($pair.Key) -cne $pair.Value'; Replacement = '$true'; Reason = 'Setting a variable to the value it already holds is a no-op; the comparison only skips the call.'}
                @{Function = 'Receive-QuietScriptsMutationJob'; Mutator = 'BlockStatement'; Original = '{$null}'; Replacement = '{}'; Reason = 'A failed read assigns nothing, which leaves the saved result null exactly as the catch value does.'}
                @{Function = 'Receive-QuietScriptsMutationJob'; Mutator = 'BlockStatement'; Original = '{Write-Verbose (''Slot worker already stopped: ''+$_.Exception.Message)}'; Replacement = '{}'; Reason = 'Write-Verbose only feeds the -Verbose stream; no result or state depends on its text.'}
                @{Function = 'Receive-QuietScriptsMutationJob'; Mutator = 'StringLiteral'; Original = '''Slot worker already stopped: '''; Replacement = ''''''; Reason = 'Write-Verbose only feeds the -Verbose stream; no result or state depends on its text.'}
                @{Function = 'Stop-QuietScriptsMutationSlot'; Mutator = 'BlockStatement'; Original = '{Write-Verbose (''Slot worker already stopped: ''+$_.Exception.Message)}'; Replacement = '{}'; Reason = 'Write-Verbose only feeds the -Verbose stream; no result or state depends on its text.'}
                @{Function = 'Stop-QuietScriptsMutationSlot'; Mutator = 'StringLiteral'; Original = '''Slot worker already stopped: '''; Replacement = ''''''; Reason = 'Write-Verbose only feeds the -Verbose stream; no result or state depends on its text.'}
                @{Function = 'Stop-QuietScriptsMutationSlot'; Mutator = 'StringLiteral'; Original = ''''''; Replacement = '''Stryker was here!'''; Reason = 'The worker only checks that the stop file exists; its content is never read.'}
            )
        }

        @{
            # Initialize-RunToolCache is covered by the Core run-profile mutation catalogue; this target covers the retry.
            Name = 'RunToolCache'
            Module = 'lib/RunToolCache.psm1'
            Functions = @('Test-RunToolTransientDownloadError','Invoke-RunToolDownload')
            UnitTestFiles = @('unit/lib/RunToolCache.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'WorkBranch'
            Module = 'lib/WorkBranch.psm1'
            Functions = @('Get-QuietWorkBranchKinds','Resolve-QuietWorkBranchName','Assert-QuietWorkBranchBase','Get-QuietWorkBranchStatusProblems','ConvertFrom-QuietWorkBranchLsRemote','Compare-QuietWorkBranchShelf')
            UnitTestFiles = @('unit/lib/WorkBranch.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'MergedBranches'
            Module = 'lib/MergedBranches.psm1'
            Functions = @('Get-QuietMergedBranchRepository','ConvertFrom-QuietMergedBranchRefs','ConvertFrom-QuietMergedBranchPullRequests','ConvertTo-QuietMergedBranchRelation','Get-QuietMergedBranchDecision','Get-QuietMergedBranchConfigSections')
            UnitTestFiles = @('unit/lib/MergedBranches.Tests.ps1')
            Break = 80
            Equivalent = @(
                @{Function = 'ConvertFrom-QuietMergedBranchPullRequests'; Mutator = 'EqualityOperator'; Original = '-gt'; Replacement = '-ge'; Reason = 'A number listed twice throws before the comparison, so two pull requests never have equal numbers and the boundary is unreachable.'}
            )
        }
        @{
            Name = 'GitHubActionReferences'
            Module = 'lib/GitHubActionReferences.psm1'
            Functions = @('Get-QuietGitHubActionFiles','ConvertFrom-QuietGitHubActionUses','Get-QuietGitHubActionRefKind','Format-QuietGitHubActionUses','Get-QuietGitHubActionRewrittenText')
            UnitTestFiles = @('unit/lib/GitHubActionReferences.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'GitHubActionReleases'
            Module = 'lib/GitHubActionReleases.psm1'
            Functions = @('Invoke-QuietGitHubActionApi','Get-QuietGitHubActionLatestRelease','Assert-QuietGitHubActionTag','Read-QuietGitHubActionReleaseCatalog','Resolve-QuietGitHubActionReleases')
            UnitTestFiles = @('unit/lib/GitHubActionReleases.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'GitHubActionUpdates'
            Module = 'lib/GitHubActionUpdates.psm1'
            Functions = @('ConvertTo-QuietGitHubActionVersion','Get-QuietGitHubActionComment','Get-QuietGitHubActionCurrentVersion','Get-QuietGitHubActionUpdate','Get-QuietGitHubActionWorkflowDocumentPath','Get-QuietGitHubActionReceiptText')
            UnitTestFiles = @('unit/lib/GitHubActionUpdates.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'PerformanceStatistics'
            Module = 'lib/PerformanceStatistics.psm1'
            Functions = @('Get-QuietPerformanceRank','Get-QuietPerformanceStatistics')
            UnitTestFiles = @('unit/lib/PerformanceStatistics.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'PerformanceWorkloads'
            Module = 'lib/PerformanceWorkloads.psm1'
            Functions = @('Get-QuietPerformanceMember','Get-QuietPerformanceItems','Get-QuietPerformanceNumbers','New-QuietPerformanceGroup','Get-QuietPerformanceHumanSamples','Get-QuietPerformanceVariantGroups','Get-QuietPerformanceWorkloadCatalog','Get-QuietPerformanceWorkloadRows','Get-QuietPerformanceRuntimeNote')
            UnitTestFiles = @('unit/lib/PerformanceWorkloads.Tests.ps1')
            Break = 80
        }
        @{
            Name = 'PerformanceCharts'
            Module = 'lib/PerformanceCharts.psm1'
            Functions = @('ConvertTo-QuietChartText','ConvertTo-QuietChartXml','Format-QuietChartNumber','Get-QuietPerformanceChartSeries','Get-QuietPerformanceChartTitle','ConvertTo-QuietPerformanceMermaidChart','Get-QuietPerformanceChartCaption','ConvertTo-QuietPerformanceSvgChart','Get-QuietPerformanceWorkloadCoverage','Get-QuietCoverageText','ConvertTo-QuietPerformanceMermaidOverview','ConvertTo-QuietPerformanceSvgOverview')
            UnitTestFiles = @('unit/lib/PerformanceCharts.Tests.ps1')
            Break = 80
        }
    )
}
