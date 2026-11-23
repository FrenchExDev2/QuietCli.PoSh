#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $source=Get-QuietTestWorkspaceRoot
    $entry=[IO.Path]::Combine($TestDrive,'scripts','Invoke-ComponentCheck.ps1')
    $scripts=[IO.Path]::GetDirectoryName($entry)
    $null=New-QuietTestFile ([IO.Path]::Combine($scripts,'lib','CompanionWorkflows.psm1')) @'
function Assert-QuietCompanionProfile {
    param($WorkspaceRoot,$Suite,$SolutionPath,$SourcePath,$TestPath)
    if($Suite -cne 'Box'){throw 'Unexpected suite'}
}
'@
    $null=New-QuietTestFile ([IO.Path]::Combine($scripts,'lib','CiCompanions.psm1')) @'
function Read-QuietCiCompanions {
    @{Companions=@{Box=@{Name='Box';Mutation=@{environment=@{QUIETCLI_BOX_MUTATION='1'}}}}}
}
function Get-QuietCompanions {
    param($Configuration,$Name,$Capability)
    if($Name -notin $Configuration.Companions.Keys){throw 'Unexpected suite'}
    if($Capability -eq 'Mutation' -and !$Configuration.Companions[$Name].Mutation){throw 'Mutation missing'}
    $Configuration.Companions[$Name].Name
}
'@
    $null=New-QuietTestFile ([IO.Path]::Combine($scripts,'Build-Workspace.ps1')) @'
param($WorkspaceRoot,$Suite,[switch]$ReuseVerifiedBuild,$RuntimeIdentifier)
if($Suite -cne 'Box' -or !$ReuseVerifiedBuild){throw 'Unexpected build selection'}
'@
    $worker=@'
param($WorkspaceRoot,$Suite,[switch]$SkipBuild,[switch]$SkipTty,$MaxConcurrency,$RunDirectory)
@{
    Suite=$Suite; Mutation=$env:QUIETCLI_BOX_MUTATION; Profile=$env:QUIETCLI_PROFILE_COMPANION
    Workers=$MaxConcurrency; SkipBuild=[bool]$SkipBuild
} | ConvertTo-Json -Compress
'@
    foreach($runner in 'Invoke-GitHubCi.ps1','Invoke-WorkspaceCi.ps1'){
        $null=New-QuietTestFile ([IO.Path]::Combine($scripts,$runner)) $worker
    }
    Copy-Item -LiteralPath ([IO.Path]::Combine($source,'scripts','Invoke-ComponentCheck.ps1')) -Destination $entry
}

Describe 'Component mutation and profiling campaigns' {
    It 'sets the declared mutation flags with one worker in sequential mode' {
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-Suite','Box','-Campaign','mutation','-Parallel:$false') -TimeoutSeconds 30
        $run.ExitCode|Should -Be 0 -Because ($run.Output+$run.Error)
        $actual=$run.Output|ConvertFrom-Json
        $actual.Suite|Should -BeExactly 'Box'
        $actual.Mutation|Should -BeExactly '1'
        $actual.Profile|Should -BeNullOrEmpty
        $actual.Workers|Should -Be 1
        $actual.SkipBuild|Should -BeTrue
    }

    It 'selects the PowerShell profiling lane independently of the mutation flags' {
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-Suite','Box','-Campaign','profiling') -TimeoutSeconds 30
        $run.ExitCode|Should -Be 0 -Because ($run.Output+$run.Error)
        $actual=$run.Output|ConvertFrom-Json
        $actual.Profile|Should -BeExactly 'Box'
        $actual.Mutation|Should -BeNullOrEmpty
        $actual.Workers|Should -BeGreaterOrEqual 1
    }

    It 'passes profiling and mutation settings to the same test runner' {
        $run=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @('-Suite','box','-Campaign','profiled-mutation') -TimeoutSeconds 30
        $run.ExitCode|Should -Be 0 -Because ($run.Output+$run.Error)
        $actual=$run.Output|ConvertFrom-Json
        $actual.Profile|Should -BeExactly 'Box'
        $actual.Mutation|Should -BeExactly '1'
    }
}
