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
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string[]]$Check=@(),[string[]]$SkipCheck=@())
$ErrorActionPreference='Stop'
# This registry is the single extension point for a new repository check.
$registry=@(
    @{Name='TestCaseMetadata';Script='Test-TestCaseMetadata.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='ScriptsReadme';Script='Sync-ScriptsReadme.ps1';Arguments=@{ScriptsPath=(Join-Path $WorkspaceRoot scripts);DocsPath=(Join-Path $WorkspaceRoot docs/scripts)}},
    @{Name='GitHubWorkflowDocs';Script='Test-GitHubWorkflowDocs.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='ScriptShouldProcess';Script='Test-ScriptShouldProcess.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='Resources';Script='Test-Resources.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='ScriptContracts';Script='Test-ScriptContracts.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot}},
    @{Name='DocsCredits';Script='Sync-DocsCredits.ps1';Arguments=@{DocsPath=(Join-Path $WorkspaceRoot docs);RootPath=$WorkspaceRoot;CreditsPath=(Join-Path $WorkspaceRoot CREDITS.md)}},
    @{Name='Credits';Script='Sync-Credits.ps1';Arguments=@{WorkspaceRoot=$WorkspaceRoot;CreditsPath=(Join-Path $WorkspaceRoot CREDITS.md)}}
)
foreach($name in @($Check)+@($SkipCheck)){if($name -cnotin $registry.Name){throw ('WorkspaceCheckUnknown: '+$name)}}
foreach($entry in $registry){
    if($Check.Count -and $entry.Name -cnotin $Check){continue}
    if($entry.Name -cin $SkipCheck){[pscustomobject]@{Check=$entry.Name;State='Skipped';Reason='Explicit SkipCheck'};continue}
    $arguments=$entry.Arguments
    Write-Host ('Progress: Validate workspace contract '+$entry.Name+'.')
    try{
        $null=& (Join-Path $PSScriptRoot $entry.Script) @arguments
        Write-Host ('Summary: '+$entry.Name+' = Success')
        [pscustomobject]@{Check=$entry.Name;State='Success'}
    }catch{
        Write-Host ('Workspace check failed: '+$entry.Name+'; '+$_.Exception.Message)
        throw
    }
}
