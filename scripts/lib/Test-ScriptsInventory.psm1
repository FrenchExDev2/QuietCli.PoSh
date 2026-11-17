#Objective: Enforces the shrink-only list of scripts/lib exports that no script test references yet.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptsInventory.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'WorkspaceJson.psm1')) -DisableNameChecking -ErrorAction Stop
Import-Module ([IO.Path]::Combine($PSScriptRoot,'ScriptsTests.psm1')) -DisableNameChecking -ErrorAction Stop

function Invoke-QuietScriptTestScriptsInventory {
    <#
    .SYNOPSIS
    Fails when an export of scripts/lib is referenced by no script test and is not listed in test/scripts/coverage.inventory.json, or when that list is stale.
    .PARAMETER WorkspaceRoot
    Workspace whose scripts/ and test/scripts/ are inventoried.
    .PARAMETER UpdateBaseline
    Writes the list pruned of entries that are now tested or no longer exported. It never adds an entry.
    #>
    param([Parameter(Mandatory)][string]$WorkspaceRoot,[switch]$UpdateBaseline)
    $WorkspaceRoot=[IO.Path]::GetFullPath($WorkspaceRoot)
    if(!(Test-QuietScriptsTestsApplicable -WorkspaceRoot $WorkspaceRoot)){return [pscustomobject][ordered]@{Check='ScriptsInventory';Applicable=$false}}
    $testsRoot=[IO.Path]::Combine($WorkspaceRoot,'test','scripts')
    $baselinePath=[IO.Path]::Combine($testsRoot,'coverage.inventory.json')
    $baseline=Read-QuietScriptsTestInventoryBaseline -Path $baselinePath
    $inventory=@(Get-QuietScriptsTestInventory -ScriptsRoot ([IO.Path]::Combine($WorkspaceRoot,'scripts')) -TestsRoot $testsRoot)
    $comparison=Compare-QuietScriptsTestInventory -Inventory $inventory -Baseline $baseline
    foreach($key in $comparison.New){Write-Host ('Untested export: '+$key)}
    foreach($key in $comparison.Stale){Write-Host ('Stale inventory entry: '+$key)}
    $pruned=$false
    if($UpdateBaseline -and $comparison.Stale.Count){
        Write-WorkspaceJson $baselinePath $comparison.Pruned
        $pruned=$true
    }
    $result=[pscustomobject][ordered]@{Check='ScriptsInventory';Exports=$comparison.Exports;Tested=$comparison.Tested;Baselined=$comparison.Baselined;New=$comparison.New.Count;Stale=$comparison.Stale.Count;Pruned=$pruned}
    if($comparison.New.Count){throw ('ScriptsInventoryUntested: '+$comparison.New.Count+'; add a test under test/scripts that exercises each export. The inventory only records legacy exports and never grows.')}
    if($comparison.Stale.Count -and !$pruned){throw ('ScriptsInventoryStale: '+$comparison.Stale.Count+'; run ./scripts/Test-ScriptsInventory.ps1 -UpdateBaseline to prune it.')}
    $result
}

Export-ModuleMember -Function Invoke-QuietScriptTestScriptsInventory
