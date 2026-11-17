#Objective: Seeded in-memory companion catalogues and workspace projects shared by the CI library tests.
#requires -Version 7.6
Import-Module ([IO.Path]::Combine($PSScriptRoot,'Generators.psm1')) -DisableNameChecking -ErrorAction Stop

function New-QuietCiProject {
    <#
    .SYNOPSIS
    Returns one workspace project record shaped like Get-QuietWorkspaceProjects output.
    .PARAMETER Group
    Solution group (companion, Tooling or Distribution).
    .PARAMETER Test
    Returns the test project of the group instead of its product project.
    #>
    param([Parameter(Mandatory)][string]$Group,[switch]$Test)
    $name=if($Test){"FrenchExDev2.QuietCli.$Group.Tests.PoSh"}else{"FrenchExDev2.QuietCli.$Group.PoSh"}
    [pscustomobject]@{Name=$name;Path="src/$Group/$(if($Test){'test'}else{'src'})/$name";SolutionGroup=$Group;IsTest=[bool]$Test}
}

function New-QuietCiCatalogue {
    <#
    .SYNOPSIS
    Returns {Configuration, Modules}: a configuration shaped like Read-QuietCiCompanions output and its projects.
    .DESCRIPTION
    Nodes come from New-QuietRandomDag, so Core is the unique base and every other companion requires it.
    Each companion has one suite (named after it or <Name>Suite), a product and a test project; Tooling
    and Distribution test projects are always present. Only Core carries core evidence.
    .PARAMETER Random
    Seeded generator.
    .PARAMETER MaxCompanions
    Upper bound of the companion count.
    #>
    param([Parameter(Mandatory)][Random]$Random,[ValidateRange(1,32)][int]$MaxCompanions=6)
    $nodes=[object[]](New-QuietRandomDag $Random ($Random.Next(1,$MaxCompanions+1)))
    $companions=[ordered]@{};$suites=[ordered]@{};$modules=[Collections.Generic.List[object]]::new()
    foreach($node in $nodes){
        $image=if($node.Name -ceq 'Core'){'base'}else{Get-QuietRandomItem $Random @('overlay','none')}
        $companions.Add($node.Name,[pscustomobject]@{Name=$node.Name;requires=@($node.Requires);Image=$image})
        $suite=if($Random.Next(0,2)){$node.Name}else{$node.Name+'Suite'}
        $tests=New-QuietCiProject $node.Name -Test
        $suites.Add($suite,[pscustomobject]@{Name=$suite;Group=$node.Name;Requires=@($node.Name);CoreEvidence=($node.Name -ceq 'Core');Qualification=@();TestsModule=$tests.Name;TestsManifest=$null;Command='Invoke-QuietXTests'})
        $modules.Add((New-QuietCiProject $node.Name));$modules.Add($tests)
    }
    $modules.Add((New-QuietCiProject Tooling -Test));$modules.Add((New-QuietCiProject Distribution -Test))
    [pscustomobject]@{Configuration=[pscustomobject]@{Path='companions.yml';SHA256=('0'*64);Companions=$companions;Suites=$suites;Base='Core'};Modules=$modules.ToArray()}
}

function Get-QuietCiOwnedPath {
    <#
    .SYNOPSIS
    Returns one changed file path owned by a companion's product or test project.
    .PARAMETER Random
    Seeded generator.
    .PARAMETER Catalogue
    New-QuietCiCatalogue output.
    .PARAMETER Companion
    Owning companion.
    #>
    param([Parameter(Mandatory)][Random]$Random,[Parameter(Mandatory)]$Catalogue,[Parameter(Mandatory)][string]$Companion)
    $module=Get-QuietRandomItem $Random @($Catalogue.Modules|Where-Object SolutionGroup -CEQ $Companion)
    $module.Path+'/'+(Get-QuietRandomItem $Random @('Public/Get-X.ps1','Private/a/b.psm1','x.psd1','data/x.json'))
}

Export-ModuleMember -Function New-QuietCiProject,New-QuietCiCatalogue,Get-QuietCiOwnedPath
