#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name ScriptsInventory
    $testsRoot=[IO.Path]::GetFullPath([IO.Path]::Combine($PSScriptRoot,'..','..'))
    $inventory=@(Get-QuietScriptsTestInventory -ScriptsRoot (Get-QuietTestScriptsRoot) -TestsRoot $testsRoot)
    $baseline=Read-QuietScriptsTestInventoryBaseline -Path ([IO.Path]::Combine($testsRoot,'coverage.inventory.json'))
}

Describe 'Script test inventory' {
    It 'references every new scripts/lib export from a test' {
        (Compare-QuietScriptsTestInventory -Inventory $inventory -Baseline $baseline).New | Should -BeNullOrEmpty -Because 'a new export needs a test under test/scripts, not an inventory entry'
    }

    It 'keeps the legacy list free of tested or removed exports' {
        (Compare-QuietScriptsTestInventory -Inventory $inventory -Baseline $baseline).Stale | Should -BeNullOrEmpty -Because 'run ./scripts/Test-ScriptsInventory.ps1 -UpdateBaseline'
    }

    It 'covers every library listed in coverage.targets.psd1' {
        $targets=Import-PowerShellDataFile ([IO.Path]::Combine($testsRoot,'coverage.targets.psd1'))
        foreach($path in @($targets.Paths)){
            $library='lib/'+[IO.Path]::GetFileName($path)
            @($baseline.Untested|Where-Object {$_.StartsWith($library+'::',[StringComparison]::Ordinal)}) | Should -BeNullOrEmpty -Because "$library is a coverage target"
        }
    }
}
