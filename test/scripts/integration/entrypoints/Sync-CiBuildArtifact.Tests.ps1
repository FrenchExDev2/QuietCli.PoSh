#requires -Version 7.6
BeforeAll {
    Import-Module ([IO.Path]::Combine($PSScriptRoot,'..','..','support','TestWorkspace.psm1')) -DisableNameChecking -ErrorAction Stop
    $entry=[IO.Path]::Combine((Get-QuietTestScriptsRoot),'Sync-CiBuildArtifact.ps1')
    Import-QuietTestLibrary -Name WorkspaceProjects
    $revision='a'*40
}

Describe 'Sync-CiBuildArtifact handoff' {
    BeforeEach {
        $fixture=[IO.Path]::Combine($TestDrive,[guid]::NewGuid().ToString('N'))
        $producer=[IO.Path]::Combine($fixture,'producer')
        $consumer=[IO.Path]::Combine($fixture,'consumer')
        $archive=[IO.Path]::Combine($fixture,'archive')
        $module='src/Core/src/FrenchExDev2.QuietCli.Core.PoSh'
        $file="$module/lib/engine/runtimes/unix/fixture.dll"
        $baseline='artifacts/ci-build-baseline/linux-x64/QuietCli.Engine'
        foreach($workspace in $producer,$consumer){
            $null=New-QuietTestFile ([IO.Path]::Combine($workspace,$module,'FrenchExDev2.QuietCli.Core.PoSh.psd1')) @'
@{
    PrivateData=@{QuietCli=@{BuildProjects=@(@{Project='engine/Fixture.csproj';Outputs=@{'net11.0'='lib/engine'}})}}
}
'@
            $null=New-QuietTestFile ([IO.Path]::Combine($workspace,$module,'engine/Fixture.csproj')) '<Project><PropertyGroup><TargetFramework>net11.0</TargetFramework></PropertyGroup></Project>'
        }
        $null=New-QuietTestFile ([IO.Path]::Combine($producer,$file)) 'portable fixture'
        $null=New-QuietTestFile ([IO.Path]::Combine($producer,$baseline)) 'IL fixture'
        $null=New-QuietTestFile ([IO.Path]::Combine($producer,'.env')) 'OWNER_ONLY=private'
        $null=New-QuietTestFile ([IO.Path]::Combine($producer,$module,'obj/project.assets.json')) 'absolute runner paths'
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList @(
            '-Mode','Export','-WorkspaceRoot',$producer,'-Directory',$archive,'-Revision',$revision,'-Baseline'
        )
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        $importArguments=@('-Mode','Import','-WorkspaceRoot',$consumer,'-Directory',$archive)
    }

    It 'preserves workspace-relative libraries and optional IL data in a fresh checkout' {
        (Get-QuietWorkspaceBuildProjects $consumer).Output|Should -BeExactly "$module/lib/engine"
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList ($importArguments+@('-Revision',$revision))
        $result.ExitCode|Should -Be 0 -Because ($result.Output+$result.Error)
        [IO.File]::ReadAllText([IO.Path]::Combine($consumer,$file))|Should -BeExactly 'portable fixture'
        [IO.File]::ReadAllText([IO.Path]::Combine($consumer,$baseline))|Should -BeExactly 'IL fixture'
        $zip=[IO.Compression.ZipFile]::OpenRead([IO.Path]::Combine($archive,'build.zip'))
        try{$zip.Entries.FullName|Sort-Object|Should -BeExactly @($baseline,$file)}finally{$zip.Dispose()}
    }

    It 'rejects a different revision or changed archive before installing files' {
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList ($importArguments+@('-Revision',('b'*40)))
        $result.ExitCode|Should -Be 1
        $result.Error|Should -Match 'CiBuildArtifactReceiptMismatch'
        Add-Content -LiteralPath ([IO.Path]::Combine($archive,'build.zip')) -Value 'modified' -Encoding utf8
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList ($importArguments+@('-Revision',$revision))
        $result.ExitCode|Should -Be 1
        $result.Error|Should -Match 'CiBuildArtifactReceiptMismatch'
        [IO.File]::Exists([IO.Path]::Combine($consumer,$file))|Should -BeFalse
    }

    It 'installs nothing in preview and refuses to overwrite an installed distribution' {
        $arguments=$importArguments+@('-Revision',$revision)
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList ($arguments+@('-WhatIf'))
        $result.ExitCode|Should -Be 0
        [IO.File]::Exists([IO.Path]::Combine($consumer,$file))|Should -BeFalse
        $null=New-QuietTestFile ([IO.Path]::Combine($consumer,$file)) 'installed fixture'
        $result=Invoke-QuietTestScript -ScriptPath $entry -ArgumentList $arguments
        $result.ExitCode|Should -Be 1
        $result.Error|Should -Match 'CiBuildArtifactDestinationExists'
        [IO.File]::ReadAllText([IO.Path]::Combine($consumer,$file))|Should -BeExactly 'installed fixture'
        [IO.File]::Exists([IO.Path]::Combine($consumer,$baseline))|Should -BeFalse
    }
}
