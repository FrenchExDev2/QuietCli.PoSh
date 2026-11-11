#requires -Version 7.6
<#
.SYNOPSIS
Checks each owning test companion's classifications and execution policy without loading its engine.
.PARAMETER WorkspaceRoot
Working tree or exported staged snapshot containing independently declared test companions.
.PARAMETER Suite
Declared companion name or All; omitted checks every discovered test companion.
.PARAMETER Plan
Returns the complete ordered scheduling plan without executing cases.
.PARAMETER MaxConcurrency
Shared worker budget used when resolving the optional plan.
#>
[CmdletBinding()]
param([string]$WorkspaceRoot=(Split-Path $PSScriptRoot -Parent),[string]$Suite='All',[switch]$Plan,[ValidateRange(1,32)][int]$MaxConcurrency=4)
$ErrorActionPreference='Stop'
Import-Module (Join-Path $PSScriptRoot 'lib/TestCaseMetadata.psm1') -ErrorAction Stop
Import-Module (Join-Path $PSScriptRoot 'lib/TestCaseScheduling.psm1') -ErrorAction Stop
. (Join-Path $PSScriptRoot 'WorkspaceProjects.ps1')
$matched=0
foreach($project in @(Get-QuietWorkspaceProjects $WorkspaceRoot|Where-Object IsTest)){
    if($Suite -cne 'All' -and $project.Name -cne ('FrenchExDev2.QuietCli.'+$Suite+'.Tests.PoSh')){continue}
    $inventory=Get-QuietCompanionTestInventory -ManifestPath $project.ManifestPath
    $name=$inventory.RunnerName.Substring('Invoke-Quiet'.Length,$inventory.RunnerName.Length-'Invoke-Quiet'.Length-'Tests'.Length)
    if($Suite -cne 'All' -and $Suite -cne $name){continue}
    $matched++
    $policy=Get-QuietTestExecutionPolicy -ManifestPath $project.ManifestPath -CaseNames $inventory.CaseNames
    $active=Get-QuietActiveCaseMetadata -Metadata $inventory.Metadata
    if($Plan){
        $executionPlan=Get-QuietTestExecutionPlan -CaseNames @($inventory.CaseNames|Where-Object {$active.ContainsKey($_)}) -Policy $policy -MaxConcurrency $MaxConcurrency
        $executionPlan|Add-Member NoteProperty Suite $name
        $executionPlan
    }else{
        [pscustomobject]@{Check='TestCaseMetadata';Suite=$name;Cases=$inventory.Count;ActiveCases=$active.Count;OptionalNotRequested=($inventory.Count-$active.Count);Unit=@($inventory.Metadata.Values|Where-Object TestKind -CEQ Unit).Count;Integration=@($inventory.Metadata.Values|Where-Object TestKind -CEQ Integration).Count;IsolatedProcess=$policy.Cases.Values.Where({$_.Mode -ceq 'IsolatedProcess'}).Count;MaxParallelCases=$policy.MaxParallelCases}
    }
}
if(!$matched){throw ('TestCaseMetadataSuiteNotFound: '+$Suite)}
