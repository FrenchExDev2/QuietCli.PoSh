#requires -Version 7.6
<#
.SYNOPSIS
Runs the shared ordered check registry used by standalone validation, GitHub and commit preparation.
.PARAMETER WorkspaceRoot
Working tree or exported staged snapshot whose contracts are checked.
.PARAMETER Check
Optional selection of registry names; omitted runs every registered check.
.PARAMETER SkipCheck
Explicit registry names omitted for this invocation; skips are reported and never called successful checks.
.PARAMETER SyncGitHubWorkflowDocs
Regenerate the workflow graphs, index and tracked map when running GitHubWorkflowDocs.
Authored workflow documentation and source receipts must already be current.
#>
[CmdletBinding(SupportsShouldProcess)]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string[]]$Check=@(),[string[]]$SkipCheck=@(),[switch]$SyncGitHubWorkflowDocs)
$ErrorActionPreference='Stop'
# This registry is the single extension point for a new repository check.
$registry=@(
    @{Name='WorkspaceSolutions';Script='Sync-WorkspaceSolutions.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='CompanionWorkflows';Script='Sync-CompanionWorkflows.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='ScriptLayout';Script='Test-ScriptLayout.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='PowerShellSources';Script='Test-PowerShellSources.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='TestCaseMetadata';Script='Test-TestCaseMetadata.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='ScriptsReadme';Script='Sync-ScriptsReadme.ps1';Arguments=@{ScriptsPath=([IO.Path]::Combine($WorkspaceRoot,'scripts'));DocsPath=([IO.Path]::Combine($WorkspaceRoot,'docs/scripts'))}},
    @{Name='GitHubWorkflowDocs';Script='Test-GitHubWorkflowDocs.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='ScriptShouldProcess';Script='Test-ScriptShouldProcess.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='ScriptAnalyzer';Script='Test-ScriptAnalysis.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='ScriptsInventory';Script='Test-ScriptsInventory.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='Resources';Script='Test-Resources.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='ScriptContracts';Script='Test-ScriptContracts.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='DocsCredits';Script='Sync-DocsCredits.ps1';Arguments=@{DocsPath=([IO.Path]::Combine($WorkspaceRoot,'docs'));RootPath=$WorkspaceRoot;CreditsPath=([IO.Path]::Combine($WorkspaceRoot,'CREDITS.md'))}},
    @{Name='Credits';Script='Sync-Credits.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot;CreditsPath=([IO.Path]::Combine($WorkspaceRoot,'CREDITS.md'))}}
)
foreach($name in @($Check)+@($SkipCheck)){if($name -cnotin $registry.Name){throw ('WorkspaceCheckUnknown: '+$name)}}
foreach($entry in $registry){
    if($Check.Count -and $entry.Name -cnotin $Check){continue}
    if($entry.Name -cin $SkipCheck){[pscustomobject]@{Check=$entry.Name;State='Skipped';Reason='Explicit SkipCheck'};continue}
    $arguments=$entry.Arguments
    Write-Host ('Progress: Validate workspace contract '+$entry.Name+'.')
    try{
        $state = 'Success'
        $apply = $false
        if ($entry.Name -ceq 'GitHubWorkflowDocs' -and $SyncGitHubWorkflowDocs) {
            $apply = $PSCmdlet.ShouldProcess($WorkspaceRoot,'Regenerate GitHub workflow documentation') -or $WhatIfPreference
        }
        if ($apply) {
            $report = & ([IO.Path]::Combine($PSScriptRoot,'Sync-GitHubWorkflowsReadme.ps1')) @arguments -Apply -WhatIf:$WhatIfPreference -Confirm:$false
            if ($report.Workflows -gt 0) {
                $outputPath = [IO.Path]::Combine($WorkspaceRoot,'docs/README-github-workflows-diagrams.md')
                $null = & ([IO.Path]::Combine($PSScriptRoot,'Export-GitHubWorkflowMap.ps1')) @arguments -OutputPath $outputPath -WhatIf:$WhatIfPreference -Confirm:$false
            }
            if ($WhatIfPreference) { $state = 'Preview' }
        } else {
            $null = & ([IO.Path]::Combine($PSScriptRoot,$entry.Script)) @arguments
        }
        Write-Host ('Summary: '+$entry.Name+' = '+$state)
        [pscustomobject]@{Check=$entry.Name;State=$state}
    }catch{
        Write-Host ('Workspace check failed: '+$entry.Name+'; '+$_.Exception.Message)
        throw
    }
}
