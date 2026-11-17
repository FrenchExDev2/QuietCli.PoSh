#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -Force -DisableNameChecking -ErrorAction Stop
    $null=Import-QuietTestLibrary -Name Test-ScriptsInventory
    # Workspace whose lib exports Get-A (tested by A.Tests.ps1 when Tested) and Get-B (never tested).
    $newWorkspace={param([string[]]$Untested,[switch]$Tested)
        $root=[IO.Path]::Combine($TestDrive,[guid]::NewGuid().ToString('N'))
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'scripts','lib','L.psm1')) "function Get-A {}`nfunction Get-B {}`nExport-ModuleMember -Function Get-A,Get-B`n"
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'test','scripts','unit','A.Tests.ps1')) $(if($Tested){'Get-A'}else{'nothing'})
        $null=New-QuietTestFile ([IO.Path]::Combine($root,'test','scripts','coverage.inventory.json')) (ConvertTo-Json -InputObject ([ordered]@{SchemaVersion=1;Untested=[string[]]@($Untested)}))
        $root
    }
    $baselineOf={param([string]$Root)(Get-Content -Raw ([IO.Path]::Combine($Root,'test','scripts','coverage.inventory.json'))|ConvertFrom-Json).Untested}
}

Describe 'Invoke-QuietScriptTestScriptsInventory' {
    BeforeEach {Mock Write-Host {} -ModuleName Test-ScriptsInventory}

    It 'passes when every untested export is listed' {
        $root=& $newWorkspace @('lib/L.psm1::Get-B') -Tested
        $result=Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $root
        $result.Check | Should -BeExactly 'ScriptsInventory'
        $result.Exports | Should -Be 2
        $result.Tested | Should -Be 1
        $result.Baselined | Should -Be 1
        $result.New | Should -Be 0
        $result.Stale | Should -Be 0
        $result.Pruned | Should -BeFalse
        Should -Invoke Write-Host -ModuleName Test-ScriptsInventory -Times 0 -Exactly
    }

    It 'fails on an untested export missing from the list and names it' {
        $root=& $newWorkspace @() -Tested
        {Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $root} | Should -Throw -ExpectedMessage 'ScriptsInventoryUntested: 1;*'
        Should -Invoke Write-Host -ModuleName Test-ScriptsInventory -Times 1 -Exactly -ParameterFilter {$Object -ceq 'Untested export: lib/L.psm1::Get-B'}
    }

    It 'fails on a stale entry without -UpdateBaseline and leaves the file alone' {
        $root=& $newWorkspace @('lib/L.psm1::Get-A','lib/L.psm1::Get-B') -Tested
        {Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $root} | Should -Throw -ExpectedMessage 'ScriptsInventoryStale: 1; run ./scripts/Test-ScriptsInventory.ps1 -UpdateBaseline to prune it.'
        Should -Invoke Write-Host -ModuleName Test-ScriptsInventory -Times 1 -Exactly -ParameterFilter {$Object -ceq 'Stale inventory entry: lib/L.psm1::Get-A'}
        (& $baselineOf $root) -join '|' | Should -BeExactly 'lib/L.psm1::Get-A|lib/L.psm1::Get-B'
    }

    It 'prunes stale entries with -UpdateBaseline' {
        $root=& $newWorkspace @('lib/Gone.psm1::Get-C','lib/L.psm1::Get-A','lib/L.psm1::Get-B') -Tested
        $result=Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $root -UpdateBaseline
        $result.Pruned | Should -BeTrue
        $result.Stale | Should -Be 2
        (& $baselineOf $root) -join '|' | Should -BeExactly 'lib/L.psm1::Get-B'
        (Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $root -UpdateBaseline).Pruned | Should -BeFalse
    }

    It 'never adds an untested export while pruning' {
        $root=& $newWorkspace @('lib/Gone.psm1::Get-C')
        {Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $root -UpdateBaseline} | Should -Throw -ExpectedMessage 'ScriptsInventoryUntested: 2;*'
        @(& $baselineOf $root).Count | Should -Be 0
    }

    It 'does not write when -UpdateBaseline finds nothing stale' {
        $root=& $newWorkspace @('lib/L.psm1::Get-B') -Tested
        $path=[IO.Path]::Combine($root,'test','scripts','coverage.inventory.json')
        $before=[IO.File]::ReadAllText($path)
        [IO.File]::SetLastWriteTimeUtc($path,[datetime]::new(2020,1,1,0,0,0,[DateTimeKind]::Utc))
        $null=Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $root -UpdateBaseline
        [IO.File]::ReadAllText($path) | Should -BeExactly $before
        [IO.File]::GetLastWriteTimeUtc($path) | Should -Be ([datetime]::new(2020,1,1,0,0,0,[DateTimeKind]::Utc))
    }

    It 'requires the baseline file' {
        $root=& $newWorkspace @()
        Remove-Item -LiteralPath ([IO.Path]::Combine($root,'test','scripts','coverage.inventory.json'))
        {Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $root} | Should -Throw -ExpectedMessage 'ScriptsInventoryBaselineMissing'
    }

    It 'is not applicable to a flat fixture without test/scripts, and fails closed on a grouped workspace' {
        $root=& $newWorkspace @('lib/L.psm1::Get-B')
        Remove-Item -LiteralPath ([IO.Path]::Combine($root,'test')) -Recurse
        $result=Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $root
        $result.Check | Should -BeExactly 'ScriptsInventory'
        $result.Applicable | Should -BeFalse
        @($result.PSObject.Properties).Count | Should -Be 2
        Should -Invoke Write-Host -ModuleName Test-ScriptsInventory -Times 0 -Exactly
        [void][IO.Directory]::CreateDirectory([IO.Path]::Combine($root,'src'))
        {Invoke-QuietScriptTestScriptsInventory -WorkspaceRoot $root} | Should -Throw -ExpectedMessage 'ScriptsTestsRootMissing: test/scripts'
    }
}
