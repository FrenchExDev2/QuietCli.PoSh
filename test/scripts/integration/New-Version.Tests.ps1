#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $entryPoint = [IO.Path]::Combine((Get-QuietTestScriptsRoot),'New-Version.ps1')
    $root = [IO.Path]::Combine($TestDrive,'workspace')
    $core = [IO.Path]::Combine($root,'src/Core/src/FrenchExDev2.QuietCli.Core.PoSh/FrenchExDev2.QuietCli.Core.PoSh.psd1')
    $vagrant = [IO.Path]::Combine($root,'src/Vagrant/src/FrenchExDev2.QuietCli.Vagrant.PoSh/FrenchExDev2.QuietCli.Vagrant.PoSh.psd1')
    $test = [IO.Path]::Combine($root,'src/Core/test/FrenchExDev2.QuietCli.Core.Tests.PoSh/FrenchExDev2.QuietCli.Core.Tests.PoSh.psd1')
    $moduleCode = [IO.Path]::ChangeExtension($core,'.psm1')
    $coreText = @'
@{
    ModuleVersion = '1.2.0'
    Description = 'Version précédente'
    PrivateData = @{ PSData = @{ Prerelease = 'preview1'; Tags = @('QuietCli') } }
}
'@
    $vagrantText = "@{ModuleVersion='0.1.0'; PrivateData=@{QuietCli=@{Publishable=`$false}}; RequiredModules=@(@{ModuleName='FrenchExDev2.QuietCli.Core.PoSh'; ModuleVersion='1.2.0'})}"
}

Describe 'New-Version.ps1' {
    BeforeEach {
        $null = New-QuietTestFile -Path $core -Text $coreText
        $null = New-QuietTestFile -Path $vagrant -Text $vagrantText
        $null = New-QuietTestFile -Path $test -Text "@{ModuleVersion='3.0.0'}"
        $null = New-QuietTestFile -Path $moduleCode -Text "throw 'A source module must never load during a metadata edit'"
    }

    It 'sets a preview, bumps its counter and then bumps patch through the public script' {
        $before = (Get-FileHash -LiteralPath $test,$moduleCode).Hash
        $run = Invoke-QuietTestScript -ScriptPath $entryPoint -ArgumentList @('-WorkspaceRoot',$root,'-Version','0.2.0-preview3')
        $run.ExitCode | Should -Be 0 -Because $run.Error
        foreach ($path in @($core,$vagrant)) {
            $data = Import-PowerShellDataFile -LiteralPath $path
            $data.ModuleVersion | Should -BeExactly '0.2.0'
            $data.PrivateData.PSData.Prerelease | Should -BeExactly 'preview3'
        }

        $run = Invoke-QuietTestScript -ScriptPath $entryPoint -ArgumentList @('-WorkspaceRoot',$root,'-Bump','preview')
        $run.ExitCode | Should -Be 0 -Because $run.Error
        foreach ($path in @($core,$vagrant)) {
            $data = Import-PowerShellDataFile -LiteralPath $path
            $data.ModuleVersion | Should -BeExactly '0.2.0'
            $data.PrivateData.PSData.Prerelease | Should -BeExactly 'preview4'
        }

        $run = Invoke-QuietTestScript -ScriptPath $entryPoint -ArgumentList @('-WorkspaceRoot',$root,'-Bump','patch')
        $run.ExitCode | Should -Be 0 -Because $run.Error
        $data = Import-PowerShellDataFile -LiteralPath $core
        $data.ModuleVersion | Should -BeExactly '0.2.1'
        $data.PrivateData.PSData.Prerelease | Should -BeNullOrEmpty
        $data.PrivateData.PSData.Tags | Should -Be @('QuietCli')
        $data.Description | Should -BeExactly 'Version précédente'
        $data = Import-PowerShellDataFile -LiteralPath $vagrant
        $data.ModuleVersion | Should -BeExactly '0.2.1'
        $data.PrivateData.PSData.Prerelease | Should -BeNullOrEmpty
        $data.RequiredModules[0].ModuleVersion | Should -BeExactly '1.2.0'
        (Get-FileHash -LiteralPath $test,$moduleCode).Hash | Should -BeExactly $before
        @(Get-ChildItem -LiteralPath $root -Recurse -File).Count | Should -Be 4
    }

    It 'forwards WhatIf and leaves every file untouched' {
        $before = (Get-FileHash -LiteralPath $core,$vagrant,$test,$moduleCode).Hash
        $run = Invoke-QuietTestScript -ScriptPath $entryPoint -ArgumentList @('-WorkspaceRoot',$root,'-Bump','patch','-WhatIf')
        $run.ExitCode | Should -Be 0 -Because $run.Error
        $run.Output | Should -Match '1\.2\.1'
        $run.Output | Should -Match '0\.1\.1'
        (Get-FileHash -LiteralPath $core,$vagrant,$test,$moduleCode).Hash | Should -BeExactly $before
        @(Get-ChildItem -LiteralPath $root -Recurse -File).Count | Should -Be 4
    }

    It 'rejects simultaneous exact version and bump modes before editing' {
        $before = (Get-FileHash -LiteralPath $core,$vagrant).Hash
        $run = Invoke-QuietTestScript -ScriptPath $entryPoint -ArgumentList @('-WorkspaceRoot',$root,'-Version','0.2.0','-Bump','patch')
        $run.ExitCode | Should -Not -Be 0
        (Get-FileHash -LiteralPath $core,$vagrant).Hash | Should -BeExactly $before
    }
}
