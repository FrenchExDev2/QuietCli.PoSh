#requires -Version 7.6

BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot, '..', '..', 'support', 'TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $module = Import-QuietTestLibrary -Name ContainerInputs
}

Describe 'Container group script inputs' {
    It 'copies only existing declared group directories once' {
        $root = [IO.Path]::Combine($TestDrive, 'workspace')
        $null = New-QuietTestFile ([IO.Path]::Combine($root, 'src/Git/scripts/Export-Reference.ps1')) '# fixture'
        $null = New-QuietTestFile ([IO.Path]::Combine($root, 'src/Core/scripts')) '# file, not a directory'
        $null = New-QuietTestFile ([IO.Path]::Combine($root, 'src/Unregistered/scripts/Ignored.ps1')) '# undiscovered group'
        $projects = @('Git', 'Core', 'Git', 'Vagrant') | ForEach-Object { [pscustomobject]@{ SolutionGroup = $_ } }
        $paths = @(& $module {
            param($workspace, $discoveredProjects)
            Get-QuietContainerGroupScripts -WorkspaceRoot $workspace -Projects $discoveredProjects
        } $root $projects)
        $paths.Count | Should -Be 1
        $paths[0] | Should -BeExactly 'src/Git/scripts'
    }
}
